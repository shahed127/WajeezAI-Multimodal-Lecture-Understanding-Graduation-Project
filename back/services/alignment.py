from dataclasses import dataclass, field
from typing import Optional, Union
import math
import os
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance, ImageOps
from sentence_transformers import SentenceTransformer
from sklearn.metrics.pairwise import cosine_similarity

from wajeezai_api.services.audio_processor import TranscriptionSegment, TranscriptionResult
from wajeezai_api.services.image_processor import SlideResult, Visual


model = SentenceTransformer("paraphrase-multilingual-MiniLM-L12-v2")


# ============================================================
# Result structures
# ============================================================

@dataclass
class TextFusion:
    ocr_chunk: str
    asr_chunks: list[TranscriptionSegment]


@dataclass
class VisualFusion:
    path: str | None
    desc: dict


@dataclass
class SlideFusion:
    slide_number: int
    texts: list[TextFusion]
    visuals: list[VisualFusion]


@dataclass
class AlignmentTextOutput:
    ocr_chunk: str
    asr_chunks: list[str] = field(default_factory=list)


@dataclass
class AlignmentVisualOutput:
    path: str
    ocr_chunk: str
    asr_chunks: list[str] = field(default_factory=list)


@dataclass
class AlignmentSlideOutput:
    slide_number: int
    texts: list[AlignmentTextOutput] = field(default_factory=list)
    visuals: list[AlignmentVisualOutput] = field(default_factory=list)


@dataclass
class AlignmentOutput:
    slides: list[AlignmentSlideOutput] = field(default_factory=list)

    @classmethod
    def from_result(cls, result: list[SlideFusion]) -> "AlignmentOutput":
        slides = []

        for slide in result:
            slide_output = AlignmentSlideOutput(slide_number=slide.slide_number)

            for text in slide.texts:
                slide_output.texts.append(
                    AlignmentTextOutput(
                        ocr_chunk=text.ocr_chunk,
                        asr_chunks=[chunk.text for chunk in text.asr_chunks],
                    )
                )

            for visual in slide.visuals:
                slide_output.visuals.append(
                    AlignmentVisualOutput(
                        path=visual.path,
                        ocr_chunk=visual.desc["ocr_chunk"],
                        asr_chunks=[chunk.text for chunk in visual.desc["asr_chunks"]],
                    )
                )

            slides.append(slide_output)

        return cls(slides=slides)


class Alignment:
    """
    Multimodal alignment between lecture images and timestamped ASR.

    Pipeline:
        timestamped ASR segments
          -> semantic ASR chunks (timestamps preserved)
          -> image OCR / visual / combined embeddings
          -> hybrid candidate retrieval
          -> threshold filtering + Top-K
          -> multimodal reranking
          -> final image-to-ASR alignment

    The existing backend contract is preserved: Alignment.align(...)
    still returns list[SlideFusion].
    """

    # Candidate retrieval weights 
    OCR_WEIGHT = 0.30
    VISUAL_WEIGHT = 0.40
    COMBINED_WEIGHT = 0.30

    # Reranking weights 
    SEMANTIC_WEIGHT = 0.40
    KEYWORD_WEIGHT = 0.20
    RERANK_VISUAL_WEIGHT = 0.30
    STRUCTURAL_WEIGHT = 0.10

    DEFAULT_THRESHOLD = 0.30
    DEFAULT_TOP_K = 3

    # backend temporal parameters.
    TEMPORAL_WEIGHT = 0.50
    SEMANTIC_RETRIEVAL_WEIGHT = 0.50
    TEMPORAL_SIGMA = 10.0

    @staticmethod
    def clean_text(text: str) -> str:
        if not text:
            return ""
        return re.sub(r"\s+", " ", str(text)).strip()

    # ============================================================
    # Timestamp-aware ASR semantic chunking
    # ============================================================

    @staticmethod
    def chunk_transcription_segments(
        segments: list[TranscriptionSegment],
        min_words: int = 25,
        max_words: int = 80,
    ) -> list[TranscriptionSegment]:
        """
        Build semantic ASR chunks while preserving timestamps.

        Every returned chunk is represented by TranscriptionSegment:
            chunk.text  -> merged ASR text
            chunk.start -> first source segment start
            chunk.end   -> last source segment end

        This is the timestamp-preserving equivalent of the notebook's
        25-80 word semantic chunking.
        """
        if not segments:
            return []

        chunks: list[TranscriptionSegment] = []
        current_texts: list[str] = []
        current_words = 0
        current_start: float | None = None
        current_end: float | None = None

        def flush_current() -> None:
            nonlocal current_texts, current_words, current_start, current_end
            if not current_texts:
                return
            text = Alignment.clean_text(" ".join(current_texts))
            if text and current_start is not None and current_end is not None:
                chunks.append(
                    TranscriptionSegment(
                        text=text,
                        start=float(current_start),
                        end=float(current_end),
                    )
                )
            current_texts = []
            current_words = 0
            current_start = None
            current_end = None

        for segment in segments:
            text = Alignment.clean_text(segment.text)
            if not text:
                continue

            words = text.split()
            n_words = len(words)

            if current_start is None:
                current_start = segment.start

            # Split unusually long source segments into <= max_words pieces.
            if n_words > max_words:
                flush_current()
                for i in range(0, n_words, max_words):
                    part = " ".join(words[i:i + max_words]).strip()
                    if not part:
                        continue
                    # We only know the source segment's time range. Distribute
                    # the timestamp proportionally across its word groups.
                    frac_start = i / n_words
                    frac_end = min(i + max_words, n_words) / n_words
                    part_start = segment.start + (segment.end - segment.start) * frac_start
                    part_end = segment.start + (segment.end - segment.start) * frac_end
                    chunks.append(
                        TranscriptionSegment(
                            text=part,
                            start=float(part_start),
                            end=float(part_end),
                        )
                    )
                continue

            if current_words + n_words <= max_words:
                current_texts.append(text)
                current_words += n_words
                current_end = segment.end
            else:
                flush_current()
                current_texts = [text]
                current_words = n_words
                current_start = segment.start
                current_end = segment.end

        flush_current()

        # Match the notebook behavior: merge very short chunks into the
        # preceding chunk, while preserving the first start and final end.
        final_chunks: list[TranscriptionSegment] = []
        for chunk in chunks:
            if final_chunks and len(chunk.text.split()) < min_words:
                previous = final_chunks[-1]
                final_chunks[-1] = TranscriptionSegment(
                    text=Alignment.clean_text(previous.text + " " + chunk.text),
                    start=previous.start,
                    end=chunk.end,
                )
            else:
                final_chunks.append(chunk)

        return final_chunks

    # ============================================================
    # Image preprocessing / crops
    # ============================================================

    @staticmethod
    def preprocess_image(
        image: Union[str, Path, np.ndarray, Image.Image],
        apply_grey: bool = False,
    ) -> Image.Image:
        if isinstance(image, (str, Path)):
            img = Image.open(image).convert("RGB")
        elif isinstance(image, np.ndarray):
            img = Image.fromarray(image).convert("RGB")
        elif isinstance(image, Image.Image):
            img = image.convert("RGB")
        else:
            raise ValueError(f"Unsupported image type: {type(image)}")

        img = img.resize((int(img.width * 1.5), int(img.height * 1.5)), Image.BICUBIC)
        if apply_grey:
            img = img.convert("L")
        img = ImageOps.exif_transpose(img)
        return ImageEnhance.Contrast(img).enhance(2)

    @staticmethod
    def crop_illustrations(
        visual: Visual,
        image_path: str,
        idx: int = 0,
        output_dir: str = "cropped_images",
    ) -> str | None:
        if not image_path or not os.path.exists(image_path):
            return None

        os.makedirs(output_dir, exist_ok=True)
        img = Alignment.preprocess_image(image_path, apply_grey=False)
        width, height = img.size

        ymin, xmin, ymax, xmax = visual.coord
        x1 = int((xmin / 1000) * width)
        y1 = int((ymin / 1000) * height)
        x2 = int((xmax / 1000) * width)
        y2 = int((ymax / 1000) * height)

        if x2 <= x1 or y2 <= y1:
            return None

        crop_path = os.path.join(
            output_dir,
            f"{Path(image_path).stem}_crop_{idx}.jpg",
        )
        img.crop((x1, y1, x2, y2)).save(crop_path)
        return crop_path

    # ============================================================
    # Embeddings
    # ============================================================

    @staticmethod
    def get_embeddings(texts: list[str]) -> np.ndarray | None:
        cleaned = [Alignment.clean_text(t) for t in texts]
        cleaned = [t for t in cleaned if t]
        if not cleaned:
            return None

        return np.asarray(
            model.encode(
                cleaned,
                batch_size=32,
                normalize_embeddings=True,
                show_progress_bar=False,
            )
        )

    @staticmethod
    def get_embedding(text: str) -> np.ndarray | None:
        text = Alignment.clean_text(text)
        if not text:
            return None
        return np.asarray(
            model.encode(text, normalize_embeddings=True, show_progress_bar=False)
        )

    # ============================================================
    # Image profiles
    # ============================================================

    @staticmethod
    def build_image_profiles(slide: SlideResult) -> list[dict]:
        """Create OCR/visual/combined profiles for one slide."""
        ocr_text = Alignment.clean_text(slide.text)
        visuals = list(slide.visuals or [])

        visual_texts = [
            Alignment.clean_text(v.desc)
            for v in visuals
            if Alignment.clean_text(v.desc)
        ]
        visual_text = "\n".join(visual_texts).strip()
        combined_text = "\n".join(
            part for part in [ocr_text, visual_text] if part
        ).strip()

        profile = {
            "image_path": slide.image_path,
            "image_name": os.path.basename(slide.image_path) if slide.image_path else "",
            "timestamp": slide.timestamp,
            "ocr_text": ocr_text,
            "visual_text": visual_text,
            "combined_text": combined_text,
            "visuals": visuals,
            "ocr_embedding": Alignment.get_embedding(ocr_text),
            "visual_embedding": Alignment.get_embedding(visual_text),
            "combined_embedding": Alignment.get_embedding(combined_text),
        }

        return [profile]

    # ============================================================
    # Temporal similarity
    # ============================================================

    @staticmethod
    def temporal_similarity(
        image_timestamp: float | None,
        segment: TranscriptionSegment,
        sigma: float = TEMPORAL_SIGMA,
    ) -> float:
        """
        Gaussian temporal similarity used by the current backend.

        The segment timestamp is represented by its midpoint. Closer image
        and ASR timestamps therefore receive higher scores.
        """
        if image_timestamp is None:
            return 0.0

        t_chunk = (float(segment.start) + float(segment.end)) / 2.0
        difference = float(image_timestamp) - t_chunk
        return float(math.exp(-(difference ** 2) / (2 * sigma ** 2)))

    # ============================================================
    # Candidate retrieval
    # ============================================================

    @staticmethod
    def calculate_hybrid_score(
        asr_embedding: np.ndarray,
        image_profile: dict,
        temporal_score: float = 0.0,
    ) -> dict:
        def sim(image_embedding: np.ndarray | None) -> float:
            if image_embedding is None:
                return 0.0
            return float(
                cosine_similarity([image_embedding], [asr_embedding])[0][0]
            )

        ocr_score = sim(image_profile.get("ocr_embedding"))
        visual_score = sim(image_profile.get("visual_embedding"))
        combined_score = sim(image_profile.get("combined_embedding"))

        semantic_score = (
            Alignment.OCR_WEIGHT * ocr_score
            + Alignment.VISUAL_WEIGHT * visual_score
            + Alignment.COMBINED_WEIGHT * combined_score
        )

        # Temporal similarity is incorporated as a second-stage retrieval
        # signal, using the backend's existing 50/50 semantic-temporal blend.
        final_score = (
            Alignment.SEMANTIC_RETRIEVAL_WEIGHT * semantic_score
            + Alignment.TEMPORAL_WEIGHT * temporal_score
        )

        return {
            "ocr_score": ocr_score,
            "visual_score": visual_score,
            "combined_score": combined_score,
            "semantic_score": semantic_score,
            "temporal_score": float(temporal_score),
            "final_score": float(final_score),
        }

    @staticmethod
    def match_images_to_asr_chunks(
        asr_chunks: list[TranscriptionSegment],
        asr_embeddings: np.ndarray | None,
        image_profile: dict,
        top_k: int = DEFAULT_TOP_K,
        min_similarity: float = DEFAULT_THRESHOLD,
    ) -> list[dict]:
        if asr_embeddings is None or not asr_chunks:
            return []

        timestamp = image_profile.get("timestamp")
        candidates = []

        for chunk_idx, (chunk, embedding) in enumerate(zip(asr_chunks, asr_embeddings)):
            temporal_score = Alignment.temporal_similarity(timestamp, chunk)
            scores = Alignment.calculate_hybrid_score(
                embedding,
                image_profile,
                temporal_score=temporal_score,
            )

            candidates.append({
                "chunk_id": chunk_idx,
                "chunk_text": chunk.text,
                "chunk": chunk,
                "chunk_embedding": embedding,
                **scores,
            })

        threshold_candidates = [
            c for c in candidates if c["final_score"] >= min_similarity
        ]
        threshold_candidates.sort(key=lambda x: x["final_score"], reverse=True)
        top_k_matches = threshold_candidates[:top_k]

        return [{
            "image_path": image_profile.get("image_path"),
            "image_name": image_profile.get("image_name"),
            "top_k_chunks": top_k_matches,
            "best_chunk": top_k_matches[0] if top_k_matches else None,
            "threshold": min_similarity,
            "num_candidates": len(candidates),
            "num_passed_threshold": len(threshold_candidates),
            "all_candidates": candidates,
        }]

    # ============================================================
    # Reranker
    # ============================================================

    @staticmethod
    def calculate_visual_score(chunk: dict, image_profile: dict) -> float:
        chunk_embedding = chunk.get("chunk_embedding")
        visuals = image_profile.get("visuals", []) or []

        per_visual_scores = []
        if chunk_embedding is not None:
            for visual in visuals:
                desc = Alignment.clean_text(visual.desc)
                if not desc:
                    continue

                if visual.__dict__.get("desc_embedding") is None:
                    # Visual is a dataclass without a declared embedding field;
                    # cache it dynamically when possible.
                    try:
                        visual.desc_embedding = Alignment.get_embedding(desc)
                    except Exception:
                        visual_embedding = Alignment.get_embedding(desc)
                    else:
                        visual_embedding = visual.desc_embedding
                else:
                    visual_embedding = visual.desc_embedding

                if visual_embedding is not None:
                    score = cosine_similarity(
                        [visual_embedding], [chunk_embedding]
                    )[0][0]
                    per_visual_scores.append(float(score))

        if per_visual_scores:
            best_visual_score = max(per_visual_scores)
        elif chunk_embedding is not None and image_profile.get("visual_embedding") is not None:
            best_visual_score = float(
                cosine_similarity(
                    [image_profile["visual_embedding"]], [chunk_embedding]
                )[0][0]
            )
        else:
            best_visual_score = 0.0

        visual_desc_text = " ".join(
            Alignment.clean_text(v.desc) for v in visuals
        ).lower()
        chunk_text = Alignment.clean_text(chunk.get("chunk_text", "")).lower()

        visual_words = set(visual_desc_text.split())
        chunk_words = set(chunk_text.split())
        visual_keyword_score = (
            len(visual_words.intersection(chunk_words)) / len(visual_words)
            if visual_words and chunk_words
            else 0.0
        )

        score = 0.75 * best_visual_score + 0.25 * visual_keyword_score
        return float(min(max(score, 0.0), 1.0))

    @staticmethod
    def calculate_structural_score(chunk: dict, image_profile: dict) -> float:
        chunk_text = Alignment.clean_text(chunk.get("chunk_text", ""))
        if not chunk_text:
            return 0.0

        chunk_lower = chunk_text.lower()

        deictic_patterns = [
            r"هذا الشكل", r"هذه الصورة", r"هذا الرسم", r"هذا المخطط",
            r"الشكل التالي", r"الصورة التالية", r"كما نرى", r"كما هو موضح",
            r"يبين الشكل", r"يوضح الشكل", r"انظر", r"لاحظ",
            r"موجود معي هنا", r"موجود عندي هنا", r"هذا الجدول",
            r"\bthis figure\b", r"\bthe diagram\b", r"\bas shown\b",
            r"\bsee figure\b", r"\bin the image\b",
        ]
        deictic_hits = sum(
            1 for pattern in deictic_patterns if re.search(pattern, chunk_lower)
        )
        deictic_score = min(deictic_hits / 2.0, 1.0)

        visuals = image_profile.get("visuals", []) or []
        visual_desc_text = " ".join(v.desc for v in visuals).lower()
        ocr_text = (image_profile.get("ocr_text") or "").lower()
        image_struct_text = f"{visual_desc_text} {ocr_text}"

        type_keywords = {
            "table": (
                ["جدول", "مقارنة", "table"],
                ["جدول", "مقارنة", "إيجابيات", "سلبيات", "table", "compare"],
            ),
            "formula": (
                ["معادلة", "صيغة", "قانون", "formula", "equation"],
                ["معادلة", "صيغة", "قانون", "formula", "يساوي"],
            ),
            "diagram": (
                ["مخطط", "رسم", "شكل", "diagram", "topology"],
                ["شكل", "رسم", "مخطط", "صورة", "topology"],
            ),
        }

        matched_types = 0
        for image_keywords, chunk_keywords in type_keywords.values():
            image_has = any(k in image_struct_text for k in image_keywords)
            chunk_has = any(k in chunk_lower for k in chunk_keywords)
            if image_has and chunk_has:
                matched_types += 1
        type_score = min(matched_types / 2.0, 1.0)

        enum_hits = len(re.findall(
            r"أولا|ثانيا|ثالثا|رابعا|أول|ثاني|ثالث|بالإضافة|كذلك",
            chunk_lower,
        ))
        bullet_hits = len(re.findall(r"[•\-*]\s", ocr_text))
        list_score = 1.0 if enum_hits > 0 and bullet_hits > 0 else 0.0

        density_score = min(len(visuals) / 3.0, 1.0)

        score = (
            0.40 * deictic_score
            + 0.30 * type_score
            + 0.20 * list_score
            + 0.10 * density_score
        )
        return float(min(max(score, 0.0), 1.0))

    @staticmethod
    def calculate_reranker_scores(chunk: dict, image_profile: dict) -> dict:
        chunk_embedding = chunk.get("chunk_embedding")
        combined_embedding = image_profile.get("combined_embedding")

        semantic_score = 0.0
        if combined_embedding is not None and chunk_embedding is not None:
            semantic_score = float(
                cosine_similarity([combined_embedding], [chunk_embedding])[0][0]
            )

        image_text = (
            (image_profile.get("ocr_text") or "")
            + " "
            + (image_profile.get("visual_text") or "")
        ).lower()
        chunk_text = (chunk.get("chunk_text") or "").lower()

        image_words = set(image_text.split())
        chunk_words = set(chunk_text.split())
        keyword_score = (
            len(image_words.intersection(chunk_words)) / len(image_words)
            if image_words and chunk_words
            else 0.0
        )

        visual_score = Alignment.calculate_visual_score(chunk, image_profile)
        structural_score = Alignment.calculate_structural_score(chunk, image_profile)

        rerank_score = (
            Alignment.SEMANTIC_WEIGHT * semantic_score
            + Alignment.KEYWORD_WEIGHT * keyword_score
            + Alignment.RERANK_VISUAL_WEIGHT * visual_score
            + Alignment.STRUCTURAL_WEIGHT * structural_score
        )

        return {
            "semantic_score": semantic_score,
            "keyword_score": float(keyword_score),
            "visual_score": visual_score,
            "structural_score": structural_score,
            "rerank_score": float(rerank_score),
        }

    @staticmethod
    def rerank_top_k_chunks(top_k_chunks: list[dict], image_profile: dict) -> list[dict]:
        reranked = []
        for chunk in top_k_chunks:
            scores = Alignment.calculate_reranker_scores(chunk, image_profile)
            reranked.append({
                "chunk_id": chunk["chunk_id"],
                "chunk_text": chunk["chunk_text"],
                "chunk": chunk["chunk"],
                "chunk_embedding": chunk["chunk_embedding"],
                "final_score": chunk["final_score"],
                "ocr_score": chunk["ocr_score"],
                "visual_score_retrieval": chunk["visual_score"],
                "combined_score": chunk["combined_score"],
                "temporal_score": chunk["temporal_score"],
                **scores,
            })

        reranked.sort(key=lambda x: x["rerank_score"], reverse=True)
        return reranked

    # ============================================================
    # One image profile -> final ASR matches
    # ============================================================

    @staticmethod
    def align_image_profile(
        image_profile: dict,
        asr_chunks: list[TranscriptionSegment],
        asr_embeddings: np.ndarray | None,
        top_k: int = DEFAULT_TOP_K,
        threshold: float = DEFAULT_THRESHOLD,
    ) -> list[dict]:
        retrieval = Alignment.match_images_to_asr_chunks(
            asr_chunks=asr_chunks,
            asr_embeddings=asr_embeddings,
            image_profile=image_profile,
            top_k=top_k,
            min_similarity=threshold,
        )
        if not retrieval:
            return []

        top_k_chunks = retrieval[0]["top_k_chunks"]
        reranked = Alignment.rerank_top_k_chunks(top_k_chunks, image_profile)
        return reranked

    # ============================================================
    # Legacy slide-text output
    # ============================================================

    @staticmethod
    def match_slide_text(
        slide_chunks: list[str],
        transcription_segments: list[TranscriptionSegment],
        threshold: float = 0.50,
        top_k_per_chunk: int = 3,
        timestamp: float | None = None,
    ) -> list[TextFusion]:
        """Legacy OCR-to-ASR matching retained for backend compatibility."""
        if not slide_chunks or not transcription_segments:
            return []

        slide_embeddings = Alignment.get_embeddings(slide_chunks)
        asr_embeddings = Alignment.get_embeddings([s.text for s in transcription_segments])
        if slide_embeddings is None or asr_embeddings is None:
            return []

        similarity_matrix = cosine_similarity(slide_embeddings, asr_embeddings)
        temporal_scores = np.array([
            Alignment.temporal_similarity(timestamp, segment)
            for segment in transcription_segments
        ])

        results = []
        for slide_idx, slide_chunk in enumerate(slide_chunks):
            final_scores = (
                Alignment.SEMANTIC_RETRIEVAL_WEIGHT * similarity_matrix[slide_idx]
                + Alignment.TEMPORAL_WEIGHT * temporal_scores
            )
            ranked = np.argsort(final_scores)[::-1]
            matched = []
            for idx in ranked:
                if float(final_scores[idx]) < threshold:
                    break
                matched.append(transcription_segments[idx])
                if len(matched) >= top_k_per_chunk:
                    break
            results.append(TextFusion(ocr_chunk=slide_chunk, asr_chunks=matched))
        return results

    # ============================================================
    # Process one slide
    # ============================================================

    @staticmethod
    def process_slide(
        slide: SlideResult,
        transcription: TranscriptionResult,
        text_threshold: float = DEFAULT_THRESHOLD,
        visual_threshold: float = DEFAULT_THRESHOLD,
        text_top_k: int = DEFAULT_TOP_K,
        visual_top_k: int = DEFAULT_TOP_K,
    ) -> SlideFusion:
        # Keep timestamped segments and create semantic chunks from them.
        asr_chunks = Alignment.chunk_transcription_segments(
            transcription.segments,
            min_words=25,
            max_words=80,
        )
        asr_embeddings = Alignment.get_embeddings([c.text for c in asr_chunks])

        # Primary multimodal fusion path from notebook 4.
        image_profiles = Alignment.build_image_profiles(slide)
        image_profile = image_profiles[0]

        reranked = Alignment.align_image_profile(
            image_profile=image_profile,
            asr_chunks=asr_chunks,
            asr_embeddings=asr_embeddings,
            top_k=visual_top_k,
            threshold=visual_threshold,
        )

        matched_segments = [item["chunk"] for item in reranked]

        # OCR text output: retain the same backend structure and use the
        # final multimodal matches rather than discarding the reranking stage.
        text_results = []
        if slide.text:
            text_results.append(
                TextFusion(
                    ocr_chunk=Alignment.clean_text(slide.text),
                    asr_chunks=matched_segments,
                )
            )

        visual_results = []
        for idx, visual in enumerate(slide.visuals or []):
            crop_path = Alignment.crop_illustrations(
                visual,
                slide.image_path,
                idx,
            ) if slide.image_path else None

            visual_results.append(
                VisualFusion(
                    path=crop_path,
                    desc={
                        "ocr_chunk": visual.desc,
                        "asr_chunks": matched_segments,
                        "reranked_matches": reranked,
                    },
                )
            )

        return SlideFusion(
            slide_number=slide.slide_number,
            texts=text_results,
            visuals=visual_results,
        )

    # ============================================================
    # Public API used by LecturePipeline
    # ============================================================

    @staticmethod
    def align(
        slides: list[SlideResult],
        transcription: TranscriptionResult,
        text_threshold: float = DEFAULT_THRESHOLD,
        visual_threshold: float = DEFAULT_THRESHOLD,
        text_top_k: int = DEFAULT_TOP_K,
        visual_top_k: int = DEFAULT_TOP_K,
    ) -> list[SlideFusion]:
        return [
            Alignment.process_slide(
                slide=slide,
                transcription=transcription,
                text_threshold=text_threshold,
                visual_threshold=visual_threshold,
                text_top_k=text_top_k,
                visual_top_k=visual_top_k,
            )
            for slide in slides
        ]
