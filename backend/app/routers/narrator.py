"""Narrator 接口：画像（免费、秒回）与叙述（要钱、按需）分成两个端点。"""

import logging

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select

from app.agents.narrator import Narrator
from app.db import get_session
from app.llm import get_provider
from app.models import NarratorBriefing
from app.schemas import MisconceptionClusterOut, NarratorBriefingOut
from app.services.profile import LearnerProfile, build_profile

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/narrator", tags=["narrator"])


def _latest_briefing(session: Session) -> NarratorBriefing | None:
    return session.exec(select(NarratorBriefing).order_by(NarratorBriefing.generated_at.desc())).first()


def _to_out(profile: LearnerProfile, briefing: NarratorBriefing | None) -> NarratorBriefingOut:
    return NarratorBriefingOut(
        total_skills=profile.total_skills,
        mastered_skills=profile.mastered_skills,
        available_skills=profile.available_skills,
        total_audits=profile.total_audits,
        passed_audits=profile.passed_audits,
        failed_audits=profile.failed_audits,
        pass_rate=profile.pass_rate,
        clusters=[
            MisconceptionClusterOut(
                label=c.label,
                occurrences=c.occurrences,
                skills=list(dict.fromkeys(c.skills)),
                cross_domain=c.cross_domain,
                first_seen=c.first_seen,
                last_seen=c.last_seen,
                principle_ids=c.principle_ids,
            )
            for c in profile.clusters
        ],
        health=profile.health,
        sanity=profile.sanity,
        focus_score=profile.focus_score,
        narrative=briefing.narrative if briefing else None,
        narrative_generated_at=briefing.generated_at if briefing else None,
    )


@router.get("/briefing", response_model=NarratorBriefingOut)
def get_briefing(session: Session = Depends(get_session)):
    """画像 + 最近一次叙述。不调用 LLM，可以随便刷。"""
    return _to_out(build_profile(session), _latest_briefing(session))


@router.post("/narrate", response_model=NarratorBriefingOut)
def narrate(session: Session = Depends(get_session)):
    """重新生成叙述。这是唯一会花钱的那个端点。"""
    profile = build_profile(session)
    try:
        narrative = Narrator(get_provider()).narrate(profile)
    except Exception:
        logger.warning("narrate failed", exc_info=True)
        raise HTTPException(502, "叙述生成失败，请稍后重试")

    briefing = NarratorBriefing(narrative=narrative)
    session.add(briefing)
    session.commit()
    session.refresh(briefing)
    return _to_out(profile, briefing)
