"""GET/PUT /api/llm (contract #46): the provider this account's agents run on. No LLM."""

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session

from app import llm
from app.db import get_session
from app.llm import usage
from app.models import Profile
from app.schemas import LLMChoiceOut, LLMIn, LLMOut

router = APIRouter(prefix="/api", tags=["llm"])


def _out() -> LLMOut:
    provider = llm.get_provider()
    return LLMOut(
        provider=provider.name,
        model=getattr(provider, "model", ""),  # the mock has none
        choices=[
            LLMChoiceOut(id=name, model=llm.default_model(name), available=llm.has_key(name))
            for name in llm.CHOICES
        ],
    )


@router.get("/llm", response_model=LLMOut)
def get_llm(session: Session = Depends(get_session)):
    return _out()


@router.put("/llm", response_model=LLMOut)
def put_llm(body: LLMIn, session: Session = Depends(get_session)):
    if not llm.has_key(body.provider):
        raise HTTPException(400, f"{body.provider} is not set up on this server")
    row = session.get(Profile, usage.PROFILE_ID) or Profile(id=usage.PROFILE_ID)
    row.llm_provider = body.provider
    session.add(row)
    session.commit()
    # get_provider reads the choice once per request: this request already has.
    ctx = usage.current()
    if ctx is not None:
        ctx.choice = body.provider
    return _out()
