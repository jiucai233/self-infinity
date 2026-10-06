"""POST /api/chat, GET /api/chat/history, GET /api/chat/suggestions (contract #18-#20).

The orchestration lives in app/services/chat.py.
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlmodel import Session

from app.db import get_session
from app.llm import get_provider
from app.schemas import ChatMessageOut, ChatRequest, ChatResponse, ChatSuggestionsResponse
from app.search import get_search_provider
from app.services import chat
from app.services.chat import FrontDeskUnavailable

router = APIRouter(prefix="/api/chat", tags=["chat"])


@router.post("", response_model=ChatResponse)
def post_message(body: ChatRequest, session: Session = Depends(get_session)):
    if body.reflection_prompt is not None:
        # Answering a reflection prompt: no LLM, no pipelines, uploads are not looked at.
        return ChatResponse(messages=chat.handle_reflection(session, body.reflection_prompt, body.message))
    # Looked up at call time (not bound at import), so the router's names can be swapped.
    try:
        attached = chat.load_uploads(session, body.upload_ids)
    except chat.UploadNotFound:
        raise HTTPException(404, "upload not found")
    try:
        messages = chat.handle_message(
            session,
            body.message,
            lambda agent: get_provider(agent),
            lambda: get_search_provider(),
            attached,
            course_topic=body.course_topic,
        )
    except FrontDeskUnavailable:
        raise HTTPException(502, "The assistant is temporarily unavailable. Please try again.")
    return ChatResponse(messages=messages)


@router.get("/history", response_model=list[ChatMessageOut])
def get_history(limit: int = Query(50, ge=1, le=200), session: Session = Depends(get_session)):
    return chat.history(session, limit)


@router.get("/suggestions", response_model=ChatSuggestionsResponse)
def get_suggestions(session: Session = Depends(get_session)):
    return ChatSuggestionsResponse(suggestions=chat.suggestions(session))
