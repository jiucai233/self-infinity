"""Voice (contract #35): speech to text and text to speech through OpenAI. No LLM prompt."""

from fastapi import APIRouter, Depends, HTTPException, Response, UploadFile

from app.auth import current_user
from app.schemas import SpeechIn, TranscriptOut, VoiceStatusOut
from app.services import voice

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
