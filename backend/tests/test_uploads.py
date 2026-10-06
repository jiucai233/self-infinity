"""Uploads (contract endpoint 24) and chat with `upload_ids` (endpoint 18)."""

import io

from pypdf import PdfWriter
from sqlmodel import Session, select

from app.models import Course, SkillNode, Upload
from app.services.uploads import MAX_UPLOAD_BYTES, MAX_UPLOAD_TEXT_CHARS
from tests.helpers import ScriptedProvider
from tests.test_chat import front_desk_json, use_provider

BAD_FILE = "Only PDF, TXT or MD files up to 4 MB."
NO_TEXT = "No text could be read from this file."

SYLLABUS = "Week 1 limits\nWeek 2 derivatives\nWeek 3 integrals\n"


def tiny_pdf(text: str) -> bytes:
    """A one-page PDF with a single line of Helvetica text (ASCII only), with a valid xref table."""
    stream = f"BT /F1 12 Tf 72 720 Td ({text}) Tj ET".encode()
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
        b"/Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    out = b"%PDF-1.4\n"
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % number + body + b"\nendobj\n"
    xref_at = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    for offset in offsets:
        out += b"%010d 00000 n \n" % offset
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref_at)
    return out


def upload(client, name: str, data: bytes, content_type: str = "application/octet-stream"):
    return client.post("/api/uploads", files={"file": (name, data, content_type)})


# ---------------------------------------------------------------- POST /api/uploads


def test_txt_upload_is_stored_and_described(client, client_engine):
    response = upload(client, "Calculus syllabus.txt", "Week 1 limits\nWeek 2 derivatives\n".encode())

    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"id", "filename", "chars", "created_at"}
    assert body["filename"] == "Calculus syllabus.txt" and body["chars"] == len("Week 1 limits\nWeek 2 derivatives")
    assert body["created_at"].endswith("Z") or body["created_at"].endswith("+00:00")
    with Session(client_engine) as session:
        row = session.get(Upload, body["id"])
    assert row.text == "Week 1 limits\nWeek 2 derivatives"


def test_md_upload_works_and_the_extension_is_case_insensitive(client):
    assert upload(client, "notes.MD", b"# Title\n\n- limits\n").status_code == 200


def test_utf8_bom_and_cp949_text_are_decoded(client, client_engine):
    bom = upload(client, "a.txt", b"\xef\xbb\xbf" + "극한".encode())
    legacy = upload(client, "b.txt", "미분".encode("cp949"))

    with Session(client_engine) as session:
        assert session.get(Upload, bom.json()["id"]).text == "극한"
        assert session.get(Upload, legacy.json()["id"]).text == "미분"


def test_pdf_upload_extracts_text(client, client_engine):
    response = upload(client, "syllabus.pdf", tiny_pdf("Limits and derivatives"), "application/pdf")

    assert response.status_code == 200
    assert response.json()["filename"] == "syllabus.pdf"
    with Session(client_engine) as session:
        assert "Limits and derivatives" in session.get(Upload, response.json()["id"]).text


def test_pdf_without_text_is_rejected(client):
    writer = PdfWriter()
    writer.add_blank_page(width=200, height=200)
    buffer = io.BytesIO()
    writer.write(buffer)

    response = upload(client, "scan.pdf", buffer.getvalue())

    assert response.status_code == 400 and response.json() == {"detail": NO_TEXT}


def test_a_corrupt_pdf_is_rejected_as_unreadable(client):
    response = upload(client, "broken.pdf", b"this is not a pdf")

    assert response.status_code == 400 and response.json() == {"detail": NO_TEXT}


def test_empty_or_whitespace_text_is_rejected(client):
    for data in (b"", b" \n\t \n"):
        response = upload(client, "empty.txt", data)
        assert response.status_code == 400 and response.json() == {"detail": NO_TEXT}


def test_other_extensions_are_rejected(client):
    for name in ("photo.png", "notes.docx", "noextension", "archive.txt.zip"):
        response = upload(client, name, b"hello")
        assert response.status_code == 400 and response.json() == {"detail": BAD_FILE}


def test_a_file_over_4_mb_is_rejected_and_exactly_4_mb_is_accepted(client):
    over = upload(client, "big.txt", b"a" * (MAX_UPLOAD_BYTES + 1))
    exact = upload(client, "limit.txt", b"a" * MAX_UPLOAD_BYTES)

    assert over.status_code == 400 and over.json() == {"detail": BAD_FILE}
    assert exact.status_code == 200


def test_stored_text_is_cut_to_100000_characters(client, client_engine):
    response = upload(client, "long.txt", b"a" * (MAX_UPLOAD_TEXT_CHARS + 500))

    assert response.json()["chars"] == MAX_UPLOAD_TEXT_CHARS
    with Session(client_engine) as session:
        assert len(session.get(Upload, response.json()["id"]).text) == MAX_UPLOAD_TEXT_CHARS


def test_a_missing_file_field_is_a_422(client):
    assert client.post("/api/uploads").status_code == 422


def test_a_rejected_upload_stores_nothing(client, client_engine):
    upload(client, "x.png", b"hello")
    upload(client, "empty.txt", b"")

    with Session(client_engine) as session:
        assert session.exec(select(Upload)).all() == []


# ---------------------------------------------------------------- POST /api/chat with upload_ids


def chat(client, message: str, upload_ids=None):
    return client.post("/api/chat", json={"message": message, "upload_ids": upload_ids})


def test_chat_with_a_file_builds_the_course_from_it(client, client_engine, monkeypatch):
    provider = use_provider(monkeypatch, ScriptedProvider())
    upload_id = upload(client, "Calculus syllabus.txt", SYLLABUS.encode()).json()["id"]

    response = chat(client, "I want to study from this file", [upload_id])

    assert response.status_code == 200
    messages = response.json()["messages"]
    assert [m["role"] for m in messages] == ["user", "assistant", "assistant"]
    action = messages[2]["action"]
    assert messages[2]["agent"] == "planner" and action["type"] == "course"
    assert action["course"]["source_course"] == "Calculus syllabus.txt"
    assert action["course"]["source_url"] is None
    # The file text replaced the Syllabus Finder: it was never called, the Planner saw the text.
    assert provider.calls_for("syllabus_finder") == []
    assert "Week 2 derivatives" in provider.system_prompts("planner")[0]
    with Session(client_engine) as session:
        course = session.exec(select(Course)).one()
        assert course.source_course == "Calculus syllabus.txt" and course.source_url is None
        assert len(session.exec(select(SkillNode)).all()) == action["node_count"]


def test_the_topic_falls_back_to_the_file_name_without_extension(client, monkeypatch):
    use_provider(monkeypatch, ScriptedProvider(front_desk=front_desk_json("none", {}, "Sure.")))
    upload_id = upload(client, "Linear algebra course.md", SYLLABUS.encode()).json()["id"]

    messages = chat(client, "Take a look at this", [upload_id]).json()["messages"]

    assert messages[2]["action"]["course"]["topic"] == "Linear algebra course"


def test_this_file_counts_as_no_topic_so_the_file_name_is_used(client):
    upload_id = upload(client, "Linear algebra course.md", SYLLABUS.encode()).json()["id"]

    for message in ("I want to learn this", "I want to study this file", "I want to learn these"):
        action = chat(client, message, [upload_id]).json()["messages"][2]["action"]
        assert action["course"]["topic"] == "Linear algebra course", message


def test_args_topic_wins_over_the_file_name(client):
    upload_id = upload(client, "syllabus.txt", SYLLABUS.encode()).json()["id"]

    messages = chat(client, "I want to learn cooking", [upload_id]).json()["messages"]

    action = messages[2]["action"]
    assert action["course"]["topic"] == "cooking" and action["course"]["source_course"] == "syllabus.txt"


def test_a_math_topic_with_a_file_does_not_get_the_searched_source(client):
    upload_id = upload(client, "my.txt", SYLLABUS.encode()).json()["id"]

    action = chat(client, "I want to learn Math", [upload_id]).json()["messages"][2]["action"]

    assert action["course"]["source_course"] == "my.txt" and action["course"]["source_url"] is None


def test_several_files_are_combined_and_named_together(client, monkeypatch):
    provider = use_provider(monkeypatch, ScriptedProvider())
    ids = [
        upload(client, "a.txt", b"alpha topics").json()["id"],
        upload(client, "b.md", b"beta topics").json()["id"],
    ]

    action = chat(client, "I want to study", ids).json()["messages"][2]["action"]

    assert action["course"]["source_course"] == "a.txt, b.md" and action["course"]["topic"] == "a"
    prompt = provider.system_prompts("planner")[0]
    assert "alpha topics" in prompt and "beta topics" in prompt


def test_other_intents_ignore_the_files(client, monkeypatch):
    use_provider(monkeypatch, ScriptedProvider(front_desk=front_desk_json("open_map", {}, "Opening it.")))
    upload_id = upload(client, "a.txt", SYLLABUS.encode()).json()["id"]

    messages = chat(client, "Show me the map", [upload_id]).json()["messages"]

    assert len(messages) == 2 and messages[1]["action"] == {"type": "navigate", "scene": "map"}


def test_a_missing_upload_is_a_404_and_nothing_is_saved(client):
    upload_id = upload(client, "a.txt", SYLLABUS.encode()).json()["id"]

    response = chat(client, "I want to study", [upload_id, 999])

    assert response.status_code == 404 and response.json() == {"detail": "upload not found"}
    assert client.get("/api/chat/history").json() == []


def test_upload_ids_is_optional_and_may_be_empty(client):
    assert client.post("/api/chat", json={"message": "Hello"}).status_code == 200
    assert chat(client, "Hello", []).status_code == 200
    assert chat(client, "Hello", None).status_code == 200


def test_a_failing_planner_with_a_file_still_answers_200_with_an_explanation(client, monkeypatch):
    use_provider(monkeypatch, ScriptedProvider(planner=lambda messages: (_ for _ in ()).throw(RuntimeError("down"))))
    upload_id = upload(client, "a.txt", SYLLABUS.encode()).json()["id"]

    response = chat(client, "I want to study", [upload_id])

    assert response.status_code == 200
    second = response.json()["messages"][2]
    assert second["agent"] == "front_desk" and second["action"] is None and second["content"] == "I couldn't build that world. Please try again in a moment."
