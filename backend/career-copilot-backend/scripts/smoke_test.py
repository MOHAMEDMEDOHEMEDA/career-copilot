import argparse
import secrets
from io import BytesIO

import httpx
from pypdf import PdfWriter
from pypdf.generic import DecodedStreamObject, DictionaryObject, NameObject


def synthetic_pdf() -> bytes:
    writer = PdfWriter()
    page = writer.add_blank_page(width=300, height=300)
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
    stream.set_data(b"BT /F1 12 Tf 50 250 Td (Synthetic resume for smoke test) Tj ET")
    page[NameObject("/Contents")] = writer._add_object(stream)
    output = BytesIO()
    writer.write(output)
    return output.getvalue()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Exercise the implemented backend flow using synthetic data."
    )
    parser.add_argument("--base-url", default="http://localhost:8000")
    args = parser.parse_args()
    credentials = {
        "email": f"smoke-{secrets.token_hex(12)}@example.com",
        "password": secrets.token_urlsafe(24),
    }
    with httpx.Client(base_url=args.base_url, timeout=30) as client:
        client.get("/health").raise_for_status()
        client.post("/api/v1/auth/register", json=credentials).raise_for_status()
        login = client.post("/api/v1/auth/login", json=credentials)
        login.raise_for_status()
        tokens = login.json()
        headers = {"Authorization": f"Bearer {tokens['access_token']}"}
        upload = client.post(
            "/api/v1/resumes",
            headers=headers,
            files={"file": ("synthetic.pdf", synthetic_pdf(), "application/pdf")},
        )
        upload.raise_for_status()
        resume_id = upload.json()["id"]
        client.get(f"/api/v1/resumes/{resume_id}", headers=headers).raise_for_status()
        client.delete(
            f"/api/v1/resumes/{resume_id}", headers=headers
        ).raise_for_status()
        client.post(
            "/api/v1/auth/logout", json={"refresh_token": tokens["refresh_token"]}
        ).raise_for_status()
    print("Health, registration, login, upload, read, delete, and logout passed.")
    print("A synthetic account remains: account deletion is not implemented yet.")


if __name__ == "__main__":
    main()
