"""
Concrete implementation of AbstractPipeline.

Wires together:
  AudioProcessor  -> transcription (ASR)
  ImageProcessor  -> slide OCR + visual detection (VLM)
  Alignment       -> fuses OCR/ASR by semantic + temporal similarity
  Syntesizer      -> renders the final Word document

Notes on deviations from the abstract signatures:
  - `process_audio` / `process_images` in the abstract class are typed as
    `-> str`, but the underlying processors return rich dataclasses
    (TranscriptionResult / list[SlideResult]) which the alignment step
    needs. Returning str here would throw away information the rest of
    the pipeline requires, so these methods return the dataclasses and a
    thin `*_status` string is exposed separately for anything that only
    wants a human-readable status line.
"""

import os
import time
import traceback
from abc import ABC, abstractmethod
from dataclasses import dataclass

from wajeezai_api.services.audio_processor import (
    AudioProcessor,
    TranscriptionResult,
    TranscriptionSegment,
)
from wajeezai_api.services.image_processor import ImageProcessor, ImageInput, SlideResult
from wajeezai_api.services.alignment import Alignment, AlignmentOutput
from wajeezai_api.services.synthesizer import Syntesizer

from google.genai import client as genai_client


class AbstractPipeline(ABC):
    def __init__(self, audio_processor, image_processor, fuser):
        self.audio_processor = audio_processor
        self.image_processor = image_processor
        self.fuser = fuser

    @abstractmethod
    def process_input(self, audio, images):
        """Process a full lecture. Must return the status of the process."""
        pass

    @abstractmethod
    def process_audio(self, audio) -> str:
        """Process audio input. Must return str if successful."""
        pass

    @abstractmethod
    def process_images(self, images) -> str:
        """Process image input. Must return str if successful."""
        pass


@dataclass
class PipelineResult:
    success: bool
    output_path: str | None = None
    error: str | None = None
    num_slides: int = 0
    duration_seconds: float = 0.0


class LecturePipeline(AbstractPipeline):
    """
    End-to-end lecture -> Word document pipeline.

    Usage:
        pipeline = LecturePipeline(
            audio_processor=AudioProcessor,
            image_processor=ImageProcessor,
            fuser=Alignment,
        )
        result = pipeline.process_input(
            audio="lecture.wav",
            images=["slide1.png", "slide2.png"],
        )
    """

    def __init__(
        self,
        audio_processor=AudioProcessor,
        image_processor=ImageProcessor,
        fuser=Alignment,
        synthesizer=Syntesizer,
        genai_api_key: str | None = None,
        subject: str = "Unknown unfortunately",
        lecture_title: str = "Unknown unfortunately",
        image_batch_size: int = 3,
        output_dir: str = "outputs",
    ):
        super().__init__(audio_processor, image_processor, fuser)
        self.synthesizer = synthesizer
        self.subject = subject
        self.lecture_title = lecture_title
        self.image_batch_size = image_batch_size
        self.output_dir = output_dir
        os.makedirs(self.output_dir, exist_ok=True)

        api_key = genai_api_key or os.getenv("GEMINI_API_KEY")
        self.synthesis_client = genai_client.Client(api_key=api_key) if api_key else None

    # ------------------------------------------------------------------
    # Audio
    # ------------------------------------------------------------------
    def process_audio(self, audio) -> TranscriptionResult:
        """
        `audio` is a path to an audio file. Returns a TranscriptionResult
        (full text + timestamped segments) built by the ASR pipeline.
        """
        print('rafaat starting process_audio')
        if not audio:
            return TranscriptionResult(full_transcription="", segments=[])

        result = self.audio_processor.transcribe_long_audio_whisper_native(
            audio_path=audio
        )

        # Guard against the pipeline returning plain dicts instead of
        # TranscriptionSegment instances (see bug note in audio_processor).
        fixed_segments = []
        for seg in result.segments:
            if isinstance(seg, TranscriptionSegment):
                fixed_segments.append(seg)
            else:
                fixed_segments.append(
                    TranscriptionSegment(
                        text=seg["text"], start=seg["start"], end=seg["end"]
                    )
                )

        return TranscriptionResult(
            full_transcription=result.full_transcription,
            segments=fixed_segments,
        )

    def process_audio_status(self, audio) -> str:
        """Thin wrapper matching the abstract `-> str` contract."""
        try:
            result = self.process_audio(audio)
            return f"ok: {len(result.segments)} segments transcribed"
        except Exception as exc:
            return f"error: {exc}"

    # ------------------------------------------------------------------
    # Images
    # ------------------------------------------------------------------
    def process_images(self, images) -> list[SlideResult]:
        """
        `images` is a list of image paths (or a list of (path, timestamp)
        tuples). Returns slides with OCR text + detected visuals, batched
        through the VLM and matched back to their source images.
        """
        print('rafaat starting process_images')
        if not images:
            return []

        image_inputs: list[ImageInput] = []
        for item in images:
            if isinstance(item, ImageInput):
                image_inputs.append(item)
            elif isinstance(item, (tuple, list)):
                path, timestamp = item
                image_inputs.append(
                    self.image_processor.load_image_input(path, timestamp=timestamp)
                )
            else:
                image_inputs.append(self.image_processor.load_image_input(item))

        slides = self.image_processor.process_images_in_batches(
            image_inputs,
            subject=self.subject,
            lecture_title=self.lecture_title,
            batch_size=self.image_batch_size,
        )
        slides = self.image_processor.attach_metadata(slides, image_inputs)
        return slides

    def process_images_status(self, images) -> str:
        """Thin wrapper matching the abstract `-> str` contract."""
        try:
            slides = self.process_images(images)
            return f"ok: {len(slides)} slides processed"
        except Exception as exc:
            return f"error: {exc}"

    # ------------------------------------------------------------------
    # Full pipeline
    # ------------------------------------------------------------------
    def process_input(
        self,
        audio,
        images,
        output_filename: str | None = None,
        cover_image_path: str | None = None,
        background_image_path: str | None = None,
    ) -> PipelineResult:
        start = time.time()
        try:
            transcription = self.process_audio(audio)
            slides = self.process_images(images)

            if not slides:
                return PipelineResult(
                    success=False,
                    error="No slides were produced from the provided images.",
                    duration_seconds=time.time() - start,
                )

            fused = self.fuser.align(slides, transcription)
            alignment_output = AlignmentOutput.from_result(fused)

            filename = output_filename or f"Lecture_Notes_{int(time.time())}.docx"
            output_path = os.path.join(self.output_dir, filename)

            self.synthesizer.create_word_doc(
                alignment_output,
                client=self.synthesis_client,
                output_docx=output_path,
                cover_image_path=cover_image_path,
                background_image_path=background_image_path,
            )

            return PipelineResult(
                success=True,
                output_path=output_path,
                num_slides=len(slides),
                duration_seconds=time.time() - start,
            )

        except Exception as exc:
            traceback.print_exc()
            return PipelineResult(
                success=False,
                error=str(exc),
                duration_seconds=time.time() - start,
            )