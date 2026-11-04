from io import BytesIO

from pypdf import PdfReader
from pypdf.errors import PdfReadError

MAX_PDF_BYTES = 10 * 1024 * 1024


class InvalidPDF(ValueError):
    pass


class PDFTooLarge(ValueError):
    pass


class PDFRequiresOCR(ValueError):
    pass


def extract_pdf_text(content: bytes, content_type: str | None) -> str:
    if len(content) > MAX_PDF_BYTES:
        raise PDFTooLarge("PDF must not exceed 10 MiB")
    if content_type != "application/pdf" or not content.startswith(b"%PDF-"):
        raise InvalidPDF("A valid PDF is required")
    try:
        reader = PdfReader(BytesIO(content), strict=True)
        if reader.is_encrypted:
            raise InvalidPDF("Encrypted PDFs are not supported")
        text = "\n".join(page.extract_text() for page in reader.pages).strip()
    except (PdfReadError, ValueError, OSError, EOFError, RecursionError) as exc:
        raise InvalidPDF("Unable to read PDF") from exc
    if not text:
        raise PDFRequiresOCR("No text found; OCR is required for scanned PDFs")
    return text
