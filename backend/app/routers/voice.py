"""Voice (contract #35): speech to text and text to speech through OpenAI, and the WebRTC
handshake of the live sessions (the home page's Guide on GPT-Live or Realtime, the audit's voice
on GPT-Live or its live transcription)."""

from fastapi import APIRouter, Depends, HTTPException, Request, Response, UploadFile
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import StreamingResponse
from sqlmodel import Session

from app.auth import CurrentUser, current_user
from app.config import settings
from app.db import account_engine, get_session
from app.models import Profile
from app.schemas import SpeechIn, TranscriptOut, VoiceChoiceIn, VoiceStatusOut, VoiceUsageIn
from app.services import realtime, voice, voice_usage

# account_engine: speech is logged in the caller's account (app/llm/usage.py).
router = APIRouter(prefix="/api/voice", tags=["voice"], dependencies=[Depends(account_engine)])

PROFILE_ID = 1  # the single Profile row


def _status(row: Profile | None) -> VoiceStatusOut:
    """What this account opens first: its own choice, else the server's (GUIDE_VOICE,
    AUDIT_VOICE)."""
    chosen = row.voice if row is not None and row.voice in ("live", "realtime") else None
    if chosen is not None:
        guide, audit = ("live", "live") if chosen == "live" else ("realtime", "turns")
    else:
        guide = "realtime" if settings.guide_voice == "realtime" else "live"
        audit = "turns" if settings.audit_voice == "turns" else "live"
        # The server's two say the same thing: that is the choice shown.
        chosen = {("live", "live"): "live", ("realtime", "turns"): "realtime"}.get((guide, audit))
    return VoiceStatusOut(available=voice.available(), guide=guide, audit=audit, choice=chosen)


@router.get("", response_model=VoiceStatusOut)
def voice_status(session: Session = Depends(get_session)):
    return _status(session.get(Profile, PROFILE_ID))


@router.put("", response_model=VoiceStatusOut)
def choose_voice(body: VoiceChoiceIn, session: Session = Depends(get_session)):
    """The account's voice: "live" (GPT-Live for the Guide and the audits) or "realtime" (the
    Realtime model for the Guide, live transcription and turns for the audits)."""
    row = session.get(Profile, PROFILE_ID) or Profile(id=PROFILE_ID)
    row.voice = body.choice
    session.add(row)
    session.commit()
    return _status(row)


@router.post("/transcribe", response_model=TranscriptOut)
def transcribe(file: UploadFile):
    # One byte past the limit, so an oversized recording is rejected without reading all of it.
    audio = file.file.read(voice.MAX_AUDIO_BYTES + 1)
    try:
        return TranscriptOut(text=voice.transcribe(audio, file.content_type, file.filename))
    except voice.VoiceUnavailable as e:
        raise HTTPException(503, str(e)) from None
    except voice.VoiceRejected as e:
        raise HTTPException(400, str(e)) from None
    except voice.VoiceFailed as e:
        raise HTTPException(502, str(e)) from None


@router.post("/speech", response_class=Response, responses={200: {"content": {"audio/mpeg": {}}}})
def speech(body: SpeechIn):
    try:
        audio = voice.speak(body.text)
    except voice.VoiceUnavailable as e:
        raise HTTPException(503, str(e)) from None
    except voice.VoiceRejected as e:
        raise HTTPException(400, str(e)) from None
    except voice.VoiceFailed as e:
        raise HTTPException(502, str(e)) from None
    return Response(content=audio, media_type="audio/mpeg")


@router.post("/speech/stream", responses={200: {"content": {"audio/pcm": {}}}})
def speech_stream(body: SpeechIn):
    try:
        chunks = voice.speak_stream(body.text)
    except voice.VoiceUnavailable as e:
        raise HTTPException(503, str(e)) from None
    except voice.VoiceRejected as e:
        raise HTTPException(400, str(e)) from None
    except voice.VoiceFailed as e:
        raise HTTPException(502, str(e)) from None
    return StreamingResponse(
        chunks,
        media_type=f"audio/pcm;rate={voice.PCM_RATE}",
        headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"},
    )


async def _offer(request: Request) -> str:
    raw = await request.body()
    if len(raw) > realtime.MAX_SDP_BYTES:
        raise HTTPException(400, "SDP offer too large")
    return raw.decode("utf-8", errors="replace")


async def _connect(offer: str, config: dict, user: CurrentUser, connect=realtime.connect) -> Response:
    try:
        answer = await run_in_threadpool(connect, offer, config, user.id)
    except voice.VoiceUnavailable as e:
        raise HTTPException(503, str(e)) from None
    except voice.VoiceRejected as e:
        raise HTTPException(400, str(e)) from None
    except voice.VoiceFailed as e:
        raise HTTPException(502, str(e)) from None
    return Response(content=answer, media_type="application/sdp", status_code=201)


@router.post("/realtime/guide", status_code=201, responses={201: {"content": {"application/sdp": {}}}})
async def realtime_guide(
    request: Request, user: CurrentUser = Depends(current_user), session: Session = Depends(get_session)
):
    offer = await _offer(request)
    if not voice.available():
        raise HTTPException(503, "voice is not configured")
    config = await run_in_threadpool(realtime.guide_session, session)
    return await _connect(offer, config, user)


@router.post("/live/guide", status_code=201, responses={201: {"content": {"application/sdp": {}}}})
async def live_guide(
    request: Request, user: CurrentUser = Depends(current_user), session: Session = Depends(get_session)
):
    """The Guide on GPT-Live: same handshake as /realtime/guide, a Live session behind it."""
    offer = await _offer(request)
    if not voice.available():
        raise HTTPException(503, "voice is not configured")
    config = await run_in_threadpool(realtime.live_guide_session, session)
    return await _connect(offer, config, user, connect=realtime.connect_live)


@router.post("/live/audit", status_code=201, responses={201: {"content": {"application/sdp": {}}}})
async def live_audit(request: Request, user: CurrentUser = Depends(current_user)):
    """An audit's voice on GPT-Live: it hands each finished answer to the browser."""
    offer = await _offer(request)
    if not voice.available():
        raise HTTPException(503, "voice is not configured")
    return await _connect(offer, realtime.live_audit_session(), user, connect=realtime.connect_live)


@router.post("/realtime/transcribe", status_code=201, responses={201: {"content": {"application/sdp": {}}}})
async def realtime_transcribe(request: Request, user: CurrentUser = Depends(current_user)):
    return await _connect(await _offer(request), realtime.transcription_session(), user)


@router.put("/sessions/{client_id}", status_code=204)
def report_usage(client_id: str, body: VoiceUsageIn, session: Session = Depends(get_session)):
    """A live session's usage so far (contract #37); the developer panel prices it."""
    if not 1 <= len(client_id) <= 64:
        raise HTTPException(400, "bad session id")
    values = body.model_dump(exclude={"started_at"})
    if body.started_at is not None:
        values["started_at"] = body.started_at
    voice_usage.report(session, client_id, values)
    return Response(status_code=204)

