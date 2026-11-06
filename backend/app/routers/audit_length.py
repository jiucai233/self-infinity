"""GET/PUT /api/audit-length (contract #53): how long this account's audits are. No LLM."""

from fastapi import APIRouter, Depends
from sqlmodel import Session

from app.db import get_session
from app.schemas import AuditLengthIn, AuditLengthOut
from app.services import audit_flow

router = APIRouter(prefix="/api", tags=["audit-length"])


@router.get("/audit-length", response_model=AuditLengthOut)
def get_audit_length(session: Session = Depends(get_session)):
    return AuditLengthOut(audit_length=audit_flow.get_audit_length(session))


@router.put("/audit-length", response_model=AuditLengthOut)
def put_audit_length(body: AuditLengthIn, session: Session = Depends(get_session)):
    audit_flow.set_audit_length(session, body.audit_length)
    return AuditLengthOut(audit_length=body.audit_length)
