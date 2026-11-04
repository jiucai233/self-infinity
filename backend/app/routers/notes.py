"""The player's own study notes on a node (contract section 52). No LLM; the notes are never
given to an agent (not to the Auditor, not to the Guide)."""

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlmodel import Session, col, select

from app.db import get_session
from app.models import NodeNote, SkillNode, utcnow
from app.schemas import NODE_NOTE_MAX, NodeNoteIn, NodeNoteOut

router = APIRouter(prefix="/api", tags=["notes"])


def _content(body: NodeNoteIn) -> str:
    content = body.content.strip()
    if not content:
        raise HTTPException(400, "note must not be empty")
    if len(content) > NODE_NOTE_MAX:
        raise HTTPException(400, f"note must be at most {NODE_NOTE_MAX} characters")
    return content


def _skill(session: Session, skill_id: int) -> SkillNode:
    skill = session.get(SkillNode, skill_id)
    if skill is None:
        raise HTTPException(404, "skill not found")
    return skill


def _note(session: Session, note_id: int) -> NodeNote:
    note = session.get(NodeNote, note_id)
    if note is None:
        raise HTTPException(404, "note not found")
    return note


@router.get("/skills/{skill_id}/notes", response_model=list[NodeNoteOut])
def list_notes(skill_id: int, session: Session = Depends(get_session)):
    """The node's notes, newest first."""
    _skill(session, skill_id)
    return session.exec(
        select(NodeNote)
        .where(NodeNote.skill_id == skill_id)
        .order_by(col(NodeNote.created_at).desc(), col(NodeNote.id).desc())
    ).all()


@router.post("/skills/{skill_id}/notes", response_model=NodeNoteOut)
def create_note(skill_id: int, body: NodeNoteIn, session: Session = Depends(get_session)):
    _skill(session, skill_id)
    now = utcnow()
    note = NodeNote(skill_id=skill_id, content=_content(body), created_at=now, updated_at=now)
    session.add(note)
    session.commit()
    session.refresh(note)
    return note


@router.put("/notes/{note_id}", response_model=NodeNoteOut)
def update_note(note_id: int, body: NodeNoteIn, session: Session = Depends(get_session)):
    note = _note(session, note_id)
    note.content = _content(body)
    note.updated_at = utcnow()
    session.add(note)
    session.commit()
    session.refresh(note)
    return note


@router.delete("/notes/{note_id}", status_code=204)
def delete_note(note_id: int, session: Session = Depends(get_session)):
    session.delete(_note(session, note_id))
    session.commit()
    return Response(status_code=204)
