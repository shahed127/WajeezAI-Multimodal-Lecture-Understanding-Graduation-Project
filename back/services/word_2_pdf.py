"""
Word (.docx) -> PDF conversion.

Two backends:
  - win32com  : uses a real Word install via COM automation. Windows-only,
                requires Microsoft Word to be installed. This is your
                original approach, kept as-is.
  - libreoffice: shells out to `soffice --headless --convert-to pdf`.
                Works on Linux/macOS/Windows as long as LibreOffice is
                installed, which is the common case for a server deployment.

`word_to_pdf` auto-picks win32com when available (i.e. running on Windows
with pywin32 + Word installed), otherwise falls back to LibreOffice. You can
also force a backend explicitly.
"""

import platform
import shutil
import subprocess
from pathlib import Path


def _word_to_pdf_win32com(word_path: Path, pdf_path: Path) -> str:
    import win32com.client

    word = win32com.client.Dispatch("Word.Application")
    word.Visible = False

    try:
        doc = word.Documents.Open(str(word_path))
        doc.SaveAs2(str(pdf_path), FileFormat=17)  # 17 = PDF
        doc.Close(False)
    finally:
        word.Quit()

    return str(pdf_path)


def _word_to_pdf_libreoffice(word_path: Path, pdf_path: Path) -> str:
    soffice = shutil.which("soffice") or shutil.which("libreoffice")
    if not soffice:
        raise RuntimeError(
            "LibreOffice ('soffice'/'libreoffice') not found on PATH. "
            "Install it, or run this on Windows with Word + pywin32 for the "
            "win32com backend."
        )

    out_dir = pdf_path.parent
    out_dir.mkdir(parents=True, exist_ok=True)

    result = subprocess.run(
        [
            soffice,
            "--headless",
            "--convert-to", "pdf",
            "--outdir", str(out_dir),
            str(word_path),
        ],
        capture_output=True,
        text=True,
        timeout=180,
    )

    if result.returncode != 0:
        raise RuntimeError(
            f"LibreOffice conversion failed (code {result.returncode}): "
            f"{result.stderr or result.stdout}"
        )

    # LibreOffice names the output after the source file's stem, regardless
    # of what we asked for — rename to the requested pdf_path if different.
    produced_path = out_dir / (word_path.stem + ".pdf")
    if not produced_path.exists():
        raise RuntimeError(
            f"LibreOffice reported success but no PDF found at {produced_path}"
        )
    if produced_path != pdf_path:
        produced_path.replace(pdf_path)

    return str(pdf_path)


def word_to_pdf(word_path: str, pdf_path: str | None = None, backend: str | None = None) -> str:
    """
    Converts a .docx to .pdf.

    backend: "win32com" | "libreoffice" | None (auto-detect: win32com on
             Windows if pywin32 is importable, else libreoffice).
    """
    word_path = Path(word_path).resolve()
    if not word_path.exists():
        raise FileNotFoundError(f"Word file not found: {word_path}")

    pdf_path = Path(pdf_path).resolve() if pdf_path else word_path.with_suffix(".pdf")

    if backend is None:
        if platform.system() == "Windows":
            try:
                import win32com.client  # noqa: F401
                backend = "win32com"
            except ImportError:
                backend = "libreoffice"
        else:
            backend = "libreoffice"

    if backend == "win32com":
        return _word_to_pdf_win32com(word_path, pdf_path)
    elif backend == "libreoffice":
        return _word_to_pdf_libreoffice(word_path, pdf_path)
    else:
        raise ValueError(f"Unknown backend: {backend}")