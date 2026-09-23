"""
Buzón real vía IMAP (Gmail u otro proveedor).

Se activa al definir en .env:
    MAIL_ADDRESS=tu_correo@gmail.com
    MAIL_APP_PASSWORD=contraseña de aplicación de 16 caracteres
    MAIL_IMAP_HOST=imap.gmail.com   (opcional)

Gmail exige una "contraseña de aplicación" (Cuenta de Google → Seguridad →
Verificación en 2 pasos → Contraseñas de aplicaciones); la contraseña normal no funciona.
"""

from datetime import timezone
from email import message_from_bytes
from email.header import decode_header, make_header
from email.message import EmailMessage, Message
from email.utils import formatdate, getaddresses, make_msgid, parsedate_to_datetime
import html
import imaplib
import os
import re
import time


IMAP_HOST = os.getenv("MAIL_IMAP_HOST", "imap.gmail.com")
MAIL_ADDRESS = os.getenv("MAIL_ADDRESS", "")
MAIL_APP_PASSWORD = os.getenv("MAIL_APP_PASSWORD", "").replace(" ", "")

URGENT_WORDS = ("urgente", "importante", "inmediato", "plazo", "vence", "urgent")


def is_configured() -> bool:
    return bool(MAIL_ADDRESS and MAIL_APP_PASSWORD)


def _connect() -> imaplib.IMAP4_SSL:
    imap = imaplib.IMAP4_SSL(IMAP_HOST, timeout=15)
    imap.login(MAIL_ADDRESS, MAIL_APP_PASSWORD)
    return imap


def _decode(value: str | None) -> str:
    if not value:
        return ""
    try:
        return str(make_header(decode_header(value)))
    except Exception:
        return value


def _plain_body(message: Message) -> str:
    """Texto del correo; si solo hay HTML, se le quitan las etiquetas."""
    html_fallback = ""
    parts = message.walk() if message.is_multipart() else [message]
    for part in parts:
        if part.get_content_maintype() == "multipart" or part.get_filename():
            continue
        payload = part.get_payload(decode=True)
        if payload is None:
            continue
        text = payload.decode(part.get_content_charset() or "utf-8", errors="replace")
        if part.get_content_type() == "text/plain":
            return text.strip()
        if part.get_content_type() == "text/html" and not html_fallback:
            without_tags = re.sub(r"(?is)<(script|style).*?</\1>|<[^>]+>", " ", text)
            html_fallback = html.unescape(without_tags)
    return re.sub(r"\s+", " ", html_fallback).strip()


def _to_record(raw: bytes, flags: bytes) -> dict:
    message = message_from_bytes(raw)
    sender_name, sender_email = (getaddresses([_decode(message.get("From"))]) or [("", "")])[0]
    subject = _decode(message.get("Subject")) or "(sin asunto)"
    body = _plain_body(message)

    try:
        date = parsedate_to_datetime(message.get("Date")).astimezone(timezone.utc).isoformat()
    except Exception:
        date = None

    flagged = b"\\Flagged" in flags
    high_priority = (message.get("X-Priority") or "").strip().startswith(("1", "2"))
    urgent_words = any(word in subject.lower() for word in URGENT_WORDS)

    return {
        "id": (message.get("Message-ID") or make_msgid()).strip("<> "),
        "sender": f"{sender_name} <{sender_email}>" if sender_name else sender_email,
        "sender_name": sender_name or sender_email,
        "recipient": _decode(message.get("To")),
        "subject": subject,
        "snippet": re.sub(r"\s+", " ", body)[:200],
        "body": body[:6000],
        "date": date,
        "is_read": b"\\Seen" in flags,
        "is_urgent": flagged or high_priority or urgent_words,
    }


def fetch_inbox(limit: int = 25, unread_only: bool = False) -> list[dict]:
    """
    Últimos `limit` correos de INBOX, del más reciente al más antiguo.
    Usa BODY.PEEK para NO marcarlos como leídos.
    """
    imap = _connect()
    try:
        imap.select("INBOX", readonly=True)
        _, data = imap.search(None, "UNSEEN" if unread_only else "ALL")
        ids = data[0].split()[-limit:]
        records = []
        for message_id in reversed(ids):
            _, parts = imap.fetch(message_id, "(FLAGS BODY.PEEK[])")
            for part in parts:
                if isinstance(part, tuple):
                    records.append(_to_record(part[1], part[0]))
        return records
    finally:
        try:
            imap.logout()
        except Exception:
            pass


def _drafts_mailbox(imap: imaplib.IMAP4_SSL) -> str:
    """Carpeta de borradores (en Gmail español es "[Gmail]/Borradores")."""
    _, mailboxes = imap.list()
    for line in mailboxes or []:
        decoded = line.decode(errors="replace")
        if "\\Drafts" in decoded:
            name = decoded.rsplit(' "/" ', 1)[-1].strip().strip('"')
            return f'"{name}"'
    return "Drafts"


def save_draft(recipient: str, subject: str, body: str) -> None:
    """Guarda el borrador en la carpeta de borradores real del usuario (no lo envía)."""
    message = EmailMessage()
    message["From"] = MAIL_ADDRESS
    message["To"] = recipient
    message["Subject"] = subject
    message["Date"] = formatdate(localtime=True)
    message.set_content(body)

    imap = _connect()
    try:
        imap.append(
            _drafts_mailbox(imap),
            "(\\Draft)",
            imaplib.Time2Internaldate(time.time()),
            message.as_bytes(),
        )
    finally:
        try:
            imap.logout()
        except Exception:
            pass
