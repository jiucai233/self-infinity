"""Voice (contract #35): speech to text and text to speech through OpenAI, and the WebRTC
handshake of the live sessions (the home page's realtime Guide, the audit's live transcription)."""

from fastapi import APIRouter, Depends, HTTPException, Request, Response, UploadFile
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import StreamingResponse
from sqlmodel import Session

from app.auth import CurrentUser, current_user
from app.db import get_session
from app.schemas import SpeechIn, TranscriptOut, VoiceStatusOut
from app.services import realtime, voice

router = APIRouter(prefix="/api/voice", tags=["voice"], dependencies=[Depends(current_user)])


@router.get("", response_model=VoiceStatusOut)
def voice_status():
    return VoiceStatusOut(available=voice.available())


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


async def _connect(offer: str, config: dict, user: CurrentUser) -> Response:
    try:
        answer = await run_in_threadpool(realtime.connect, offer, config, user.id)
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


@router.post("/realtime/transcribe", status_code=201, responses={201: {"content": {"application/sdp": {}}}})
async def realtime_transcribe(request: Request, user: CurrentUser = Depends(current_user)):
    return await _connect(await _offer(request), realtime.transcription_session(), user)

