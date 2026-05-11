from __future__ import annotations

from pathlib import Path
from typing import Any

from reportlab.lib import colors
from reportlab.pdfgen.canvas import Canvas

from ..models import WifiRecord
from .common import draw_logo, draw_qr, fit_font_size


QR_LOGO_PATH = Path(__file__).resolve().parents[2] / "assets" / "wifi_pdf" / "qr-code-logo.png"

QR_THEME = {
    "page_background": colors.white,
    "title_text": colors.HexColor("#0F172A"),
    "body_text": colors.HexColor("#0A4F94"),
    "qr_border": colors.HexColor("#D7E0E8"),
}


def _centered_text(
    canvas: Canvas,
    text: str,
    y: float,
    max_width: float,
    font_name: str,
    start_size: int,
    minimum_size: int,
    color: colors.Color,
) -> None:
    page_width, _ = canvas._pagesize
    font_size = fit_font_size(text, font_name, max_width, start_size, minimum_size)
    canvas.setFillColor(color)
    canvas.setFont(font_name, font_size)
    canvas.drawCentredString(page_width / 2, y, text)


def draw_qr_code_template(
    canvas: Canvas,
    record: WifiRecord,
    building_name: str,
    qr_path: Path,
    settings: Any,
    fonts: dict[str, str],
    sheet_number: int,
    sheet_total: int,
) -> None:
    page_width, page_height = canvas._pagesize
    margin = 28
    unit_label = (record.unit_label or record.ssid).strip()
    title = unit_label or record.ssid

    canvas.setTitle(f"QR {building_name} - {title}")
    canvas.setAuthor(settings.branding.brand_name)
    canvas.setFillColor(QR_THEME["page_background"])
    canvas.rect(0, 0, page_width, page_height, fill=1, stroke=0)

    logo_path = QR_LOGO_PATH if QR_LOGO_PATH.exists() else settings.branding.logo_path
    logo_width = 76
    logo_height = 76
    draw_logo(
        canvas,
        logo_path,
        (page_width - logo_width) / 2,
        page_height - margin - logo_height,
        logo_width,
        logo_height,
    )

    text_width = page_width - (2 * margin)
    unit_y = page_height - margin - logo_height - 42
    _centered_text(
        canvas,
        title,
        unit_y,
        text_width,
        fonts["bold"],
        34,
        16,
        QR_THEME["title_text"],
    )

    message_fr = "Scannez-moi pour vous connecter au Wi-Fi"
    message_en = "Scan me to connect to the Wi-Fi"
    _centered_text(
        canvas,
        message_fr,
        unit_y - 36,
        text_width,
        fonts["bold"],
        18,
        11,
        QR_THEME["body_text"],
    )
    _centered_text(
        canvas,
        message_en,
        unit_y - 59,
        text_width,
        fonts["regular"],
        17,
        10,
        QR_THEME["body_text"],
    )

    qr_top = unit_y - 88
    qr_bottom = margin
    available_height = qr_top - qr_bottom
    qr_size = min(page_width - (2 * margin), available_height)
    qr_x = (page_width - qr_size) / 2
    qr_y = qr_bottom + ((available_height - qr_size) / 2)

    canvas.saveState()
    canvas.setStrokeColor(QR_THEME["qr_border"])
    canvas.setLineWidth(1.2)
    canvas.rect(qr_x - 4, qr_y - 4, qr_size + 8, qr_size + 8, stroke=1, fill=0)
    canvas.restoreState()
    draw_qr(canvas, qr_path, qr_x, qr_y, qr_size, qr_size)
