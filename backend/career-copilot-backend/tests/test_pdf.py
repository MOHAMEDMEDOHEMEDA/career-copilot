from io import BytesIO

import pytest
from pypdf import PdfWriter
from pypdf.generic import DecodedStreamObject, DictionaryObject, NameObject

from career_copilot_backend.parsing.pdf import (
    MAX_PDF_BYTES,
    InvalidPDF,
    PDFRequiresOCR,
    PDFTooLarge,
    extract_pdf_text,
)


def make_pdf(text: bool) -> bytes:
    writer = PdfWriter()
    page = writer.add_blank_page(width=300, height=300)
    if text:
        font = DictionaryObject(
            {
                NameObject("/Type"): NameObject("/Font"),
                NameObject("/Subtype"): NameObject("/Type1"),
                NameObject("/BaseFont"): NameObject("/Helvetica"),
            }
        )
        page[NameObject("/Resources")] = DictionaryObject(
            {
                NameObject("/Font"): DictionaryObject(
                    {NameObject("/F1"): writer._add_object(font)}
                )
            }
        )
        stream = DecodedStreamObject()
        stream.set_data(b"BT /F1 12 Tf 50 250 Td (Synthetic resume) Tj ET")
        page[NameObject("/Contents")] = writer._add_object(stream)
    output = BytesIO()
    writer.write(output)
    return output.getvalue()


def test_extracts_text() -> None:
    assert "Synthetic resume" in extract_pdf_text(make_pdf(True), "application/pdf")


def test_empty_pdf_requires_ocr() -> None:
    with pytest.raises(PDFRequiresOCR):
        extract_pdf_text(make_pdf(False), "application/pdf")


@pytest.mark.parametrize(
    "content, content_type",
    [
        (b"not a pdf", "application/pdf"),
        (b"%PDF-invalid", "application/pdf"),
        (b"%PDF-", "text/plain"),
    ],
)
def test_rejects_invalid_pdf(content: bytes, content_type: str) -> None:
    with pytest.raises(InvalidPDF):
        extract_pdf_text(content, content_type)


def test_rejects_oversized_pdf() -> None:
    with pytest.raises(PDFTooLarge):
        extract_pdf_text(b"x" * (MAX_PDF_BYTES + 1), "application/pdf")
