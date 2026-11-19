"""
FastAPI service for the lecture -> Word document pipeline.

Flow:
  1. POST /api/lectures/upload                 -> saves audio + slides + timestamps.json
                                                    under uploads/{lecture_id}/, returns lecture_id
  2. POST /api/lectures/{lecture_id}/process       -> runs the pipeline against those saved
                                                    files, writes outputs/{lecture_id}/Lecture_Notes.docx
  3. GET  /api/lectures/{lecture_id}/status        -> poll while (2) runs in the background
  4. GET  /api/lectures/{lecture_id}/download      -> fetch the finished .docx
  5. GET  /api/lectures                            -> list all lectures + their status
  6. POST /api/lectures/{lecture_id}/convert-pdf   -> convert the finished .docx to .pdf
  7. GET  /api/lectures/{lecture_id}/download-pdf  -> fetch the finished .pdf

timestamps.json format expected from the client (dict keyed by slide filename):
    {
      "slide_1.png": 12.5,
      "slide_2.png": 48.0
    }
"""

import json
import os
import time
import traceback

from fastapi import BackgroundTasks, FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse

from wajeezai_api.services.pipeline import LecturePipeline
from wajeezai_api.services.word_2_pdf import word_to_pdf

app = FastAPI()

# Flutter web runs from a different origin (e.g. http://localhost:<random-port>
# when using `flutter run -d chrome`, or wherever it's hosted) than this API
# (http://127.0.0.1:8000), so the browser enforces CORS on every request.
# Without this, the browser silently blocks the response before Dart ever
# sees it, which surfaces as "ClientException: Failed to fetch" even though
# the request reaches the server fine (visible as a 200 in the uvicorn logs).
#
# allow_origins=["*"] is convenient for local dev; lock this down to your
# actual deployed frontend origin(s) before shipping to production.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    return {"message": "Hello World"}


UPLOAD_DIR = "uploads"
OUTPUT_DIR = "outputs"
os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(OUTPUT_DIR, exist_ok=True)

# In-memory status store, keyed by lecture_id. Swap for Redis/DB in production —
# this resets if the process restarts, and won't survive multiple worker
# processes either (each would have its own dict). Fine for a single-process
# dev/staging setup; a real deployment should persist this (e.g. a lectures
# table) so /api/lectures can survive restarts and work across workers.
LECTURE_STATUS: dict[str, dict] = {}


def _default_status(status: str = "uploaded") -> dict:
    return {
        "status": status,
        "output_path": None,
        "pdf_path": None,
        "pdf_status": None,
        "pdf_error": None,
        "error": None,
        "num_slides": 0,
        "duration_seconds": 0.0,
        "created_at": time.time(),
        "title": None,
    }


# ----------------------------------------------------------------------
# 1. Upload
# ----------------------------------------------------------------------
@app.post("/api/lectures/upload")
async def upload_lecture(
    audio: UploadFile = File(...),
    slides: list[UploadFile] = File(default=[]),
    timestamps: UploadFile = File(...),
    title: str | None = None,
):
    lecture_id = "lecture_" + str(int(time.time()))
    lecture_dir = os.path.join(UPLOAD_DIR, lecture_id)
    os.makedirs(lecture_dir, exist_ok=True)

    # Save audio
    audio_path = os.path.join(lecture_dir, "lecture.wav")
    with open(audio_path, "wb") as f:
        while chunk := await audio.read(1024 * 1024):
            f.write(chunk)

    # Save slides
    slide_filenames = []
    for slide in slides:
        filename = os.path.basename(slide.filename)
        slide_path = os.path.join(lecture_dir, filename)
        with open(slide_path, "wb") as f:
            while chunk := await slide.read(1024 * 1024):
                f.write(chunk)
        slide_filenames.append(filename)

    # Read and save timestamps
    try:
        timestamps_content = await timestamps.read()
        timestamps_data = json.loads(timestamps_content)

        timestamps_path = os.path.join(lecture_dir, "timestamps.json")
        with open(timestamps_path, "w", encoding="utf-8") as f:
            json.dump(timestamps_data, f, ensure_ascii=False, indent=2)

    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="Invalid timestamps JSON")

    status = _default_status("uploaded")
    status["title"] = title or lecture_id
    LECTURE_STATUS[lecture_id] = status

    return {
        "status": "ok",
        "lecture_id": lecture_id,
        "slides": len(slide_filenames),
    }


# ----------------------------------------------------------------------
# 2. Process
# ----------------------------------------------------------------------
def _run_pipeline_for_lecture(lecture_id: str, lecture_dir: str):
    print('qusai')
    """Runs in the background so /process returns immediately."""
    LECTURE_STATUS[lecture_id]["status"] = "processing"
    try:
        timestamps_path = os.path.join(lecture_dir, "timestamps.json")
        with open(timestamps_path, "r", encoding="utf-8") as f:
            timestamps_data = json.load(f)

        # Build (path, timestamp) pairs in the order they appear in
        # timestamps.json. Files not listed there (e.g. an accidental
        # extra upload) are skipped rather than silently guessed at.
        image_inputs = []
        for filename, ts in timestamps_data.items():
            slide_path = os.path.join(lecture_dir, filename)
            if not os.path.exists(slide_path):
                print(f"Warning: {filename} listed in timestamps.json but not found on disk, skipping.")
                continue
            image_inputs.append((slide_path, float(ts)))

        if not image_inputs:
            raise ValueError("No valid slides found for this lecture (check timestamps.json vs uploaded filenames).")

        audio_path = os.path.join(lecture_dir, "lecture.wav")

        lecture_output_dir = os.path.join(OUTPUT_DIR, lecture_id)
        os.makedirs(lecture_output_dir, exist_ok=True)

        pipeline = LecturePipeline(output_dir=lecture_output_dir)
        result = pipeline.process_input(
            audio=audio_path,
            images=image_inputs,
            output_filename="Lecture_Notes.docx",
        )

        if result.success:
            LECTURE_STATUS[lecture_id].update(
                status="processing_complete",
                output_path=result.output_path,
                num_slides=result.num_slides,
                duration_seconds=result.duration_seconds,
            )
        else:
            LECTURE_STATUS[lecture_id].update(status="failed", error=result.error)

    except Exception as exc:
        print('danial exeption')
        traceback.print_exc()
        LECTURE_STATUS[lecture_id].update(status="failed", error=str(exc))


@app.post("/api/lectures/{lecture_id}/process")
async def process_lecture(lecture_id: str, background_tasks: BackgroundTasks):
    print('process_lecture')
    lecture_dir = os.path.join(UPLOAD_DIR, lecture_id)
    if not os.path.isdir(lecture_dir):
        raise HTTPException(404, "Lecture not found")

    if lecture_id not in LECTURE_STATUS:
        LECTURE_STATUS[lecture_id] = _default_status("uploaded")

    LECTURE_STATUS[lecture_id]["status"] = "queued"
    background_tasks.add_task(_run_pipeline_for_lecture, lecture_id, lecture_dir)

    return {"status": "processing_queued", "lecture_id": lecture_id}


# ----------------------------------------------------------------------
# 3. Status
# ----------------------------------------------------------------------
@app.get("/api/lectures/{lecture_id}/status")
async def lecture_status(lecture_id: str):
    status = LECTURE_STATUS.get(lecture_id)
    if status is None:
        raise HTTPException(404, "Lecture not found")
    return {"lecture_id": lecture_id, **status}


# ----------------------------------------------------------------------
# 4. Download docx
# ----------------------------------------------------------------------
@app.get("/api/lectures/{lecture_id}/download")
async def download_lecture(lecture_id: str):
    status = LECTURE_STATUS.get(lecture_id)
    if status is None:
        raise HTTPException(404, "Lecture not found")
    if status["status"] != "processing_complete":
        raise HTTPException(409, f"Lecture status is '{status['status']}', not ready for download.")

    return FileResponse(
        path=status["output_path"],
        filename="Lecture_Notes.docx",
        media_type=(
            "application/vnd.openxmlformats-officedocument"
            ".wordprocessingml.document"
        ),
    )


# ----------------------------------------------------------------------
# 5. List lectures
# ----------------------------------------------------------------------
@app.get("/api/lectures")
async def list_lectures():
    """
    Returns every known lecture with its current status, newest first.
    Includes booleans for what actions are currently available, so a
    frontend doesn't have to re-derive them from `status` strings.
    """
    lectures = []
    for lecture_id, status in LECTURE_STATUS.items():
        lectures.append({
            "lecture_id": lecture_id,
            "title": status.get("title") or lecture_id,
            "status": status["status"],
            "num_slides": status["num_slides"],
            "duration_seconds": status["duration_seconds"],
            "error": status["error"],
            "created_at": status["created_at"],
            "pdf_status": status.get("pdf_status"),
            "can_download_docx": status["status"] == "processing_complete",
            "can_convert_pdf": status["status"] == "processing_complete",
            "can_download_pdf": status.get("pdf_status") == "done",
        })

    lectures.sort(key=lambda l: l["created_at"], reverse=True)
    return {"lectures": lectures, "count": len(lectures)}


# ----------------------------------------------------------------------
# 6. Convert to PDF
# ----------------------------------------------------------------------
def _run_pdf_conversion(lecture_id: str):
    status = LECTURE_STATUS[lecture_id]
    status["pdf_status"] = "converting"
    try:
        docx_path = status["output_path"]
        pdf_path = os.path.splitext(docx_path)[0] + ".pdf"
        result_path = word_to_pdf(docx_path, pdf_path)
        status["pdf_path"] = result_path
        status["pdf_status"] = "done"
        status["pdf_error"] = None
    except Exception as exc:
        traceback.print_exc()
        status["pdf_status"] = "failed"
        status["pdf_error"] = str(exc)


@app.post("/api/lectures/{lecture_id}/convert-pdf")
async def convert_lecture_to_pdf(lecture_id: str, background_tasks: BackgroundTasks):
    status = LECTURE_STATUS.get(lecture_id)
    if status is None:
        raise HTTPException(404, "Lecture not found")
    if status["status"] != "processing_complete":
        raise HTTPException(409, f"Lecture status is '{status['status']}'; the .docx must finish generating before it can be converted to PDF.")

    status["pdf_status"] = "queued"
    status["pdf_error"] = None
    background_tasks.add_task(_run_pdf_conversion, lecture_id)

    return {"status": "pdf_conversion_queued", "lecture_id": lecture_id}


# ----------------------------------------------------------------------
# 7. Download PDF
# ----------------------------------------------------------------------
@app.get("/api/lectures/{lecture_id}/download-pdf")
async def download_lecture_pdf(lecture_id: str):
    status = LECTURE_STATUS.get(lecture_id)
    if status is None:
        raise HTTPException(404, "Lecture not found")
    if status.get("pdf_status") != "done" or not status.get("pdf_path"):
        raise HTTPException(409, f"PDF not ready (pdf_status='{status.get('pdf_status')}'). Call convert-pdf first.")

    return FileResponse(
        path=status["pdf_path"],
        filename="Lecture_Notes.pdf",
        media_type="application/pdf",
    )