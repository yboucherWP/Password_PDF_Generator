from __future__ import annotations

from pathlib import Path
from typing import Any

from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfgen.canvas import Canvas
from reportlab.platypus import Paragraph

from ..models import WifiRecord


LABEL_NETWORK = "Nom du réseau | Network name"
LABEL_PASSWORD = "Mot de passe | Password"
FR_TITLE = "Instructions en français :"
EN_TITLE = "English Instructions:"
KEEP_LINE = "Gardez cette feuille comme référence | Keep this paper for future use"
TECH_TITLE = "Pour des problèmes de connexion ou des questions techniques | For any technical problems or questions"
IPTV_TITLE = "Pour toutes questions sur la télévision IP: | For any questions regarding the IPTV:"
CLOSING_LINE = "Informez-vous aussi de nos autres services comme la téléphonie IP | Ask us as well about our other services, such as VoIP."
QR_NOTE_FR = "À l'aide de votre appareil intelligent, vous pouvez scanner ce code QR pour accéder à votre réseau WiFi automatiquement sans y rentrer un mot de passe."
QR_NOTE_EN = "With the help of your phone/tablet, you can scan this QR code to access your WiFi Network automatically."

FR_ITEMS = [
    "Le nom du réseau WIFI que vous devez utiliser est votre numéro de porte (ex : wp101, porte101)",
    "Vous trouverez ci-joint le nom du réseau et le mot de passe à utiliser pour se connecter au réseau",
    "Veuillez respecter les minuscules et majuscules dans le mot de passe",
    "Lorsque vous vous branchez au réseau internet de l’immeuble, vous reconnaissez avoir lu et accepté les termes et conditions sur cette page : wifiplex.ca/termes",
    "Tous vos appareils sont compatibles avec le Wifi. Veuillez contacter notre équipe de support si l'un de vos périphériques n'arrive pas à se connecter.",
]

EN_ITEMS = [
    "The network name that you need to use is your unit number (ex : wp101, porte101)",
    "Please respect lower and upper cases in the password",
    "When you connect to the building’s internet network, you acknowledge that you have read and accepted the terms and conditions on this page : wifiplex.ca/terms",
    "All your devices are compatible with the Wifi. If some require a special configuration, please contact us if any of your devices cannot connect",
]

TECH_ITEMS = [
    "Clavardage en ligne | Live chat www.wifiplex.ca",
    "Envoyez un courriel | Email us Support@WifiPlex.ca",
    "514-556-1556 #2 ou Sans Frais | Toll-free 1-888-777-9778 #2",
]

IPTV_ITEMS = [
    "https://wifiplex.tv",
    "tv@wifiplex.ca",
    "514-556-1556 option 2.",
]


def draw_card(
    canvas: Canvas,
    x: float,
    y: float,
    width: float,
    height: float,
    fill_color: colors.Color,
    radius: float,
    stroke_color: colors.Color | None = None,
) -> None:
    canvas.saveState()
    canvas.setFillColor(fill_color)
    canvas.setStrokeColor(stroke_color or fill_color)
    canvas.roundRect(x, y, width, height, radius, stroke=1 if stroke_color else 0, fill=1)
    canvas.restoreState()


def draw_paragraph(
    canvas: Canvas,
    text: str,
    x: float,
    y_top: float,
    width: float,
    font_name: str,
    font_size: float,
    color: colors.Color,
    leading: float | None = None,
    bold_fragments: bool = False,
) -> float:
    paragraph_text = text if bold_fragments else text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    style = ParagraphStyle(
        name=f"style-{font_name}-{font_size}",
        fontName=font_name,
        fontSize=font_size,
        leading=leading or font_size * 1.25,
        textColor=color,
        spaceAfter=0,
        spaceBefore=0,
    )
    paragraph = Paragraph(paragraph_text.replace("\n", "<br/>"), style)
    _, height = paragraph.wrap(width, 10_000)
    paragraph.drawOn(canvas, x, y_top - height)
    return height


def fit_font_size(value: str, font_name: str, max_width: float, start: int, minimum: int) -> int:
    font_size = start
    while font_size > minimum and pdfmetrics.stringWidth(value, font_name, font_size) > max_width:
        font_size -= 1
    return font_size


def draw_logo(canvas: Canvas, logo_path: Path | None, x: float, y: float, width: float, height: float) -> None:
    if not logo_path or not logo_path.exists():
        return
    canvas.drawImage(
        ImageReader(str(logo_path)),
        x,
        y,
        width=width,
        height=height,
        preserveAspectRatio=True,
        mask="auto",
    )


def draw_qr(canvas: Canvas, qr_path: Path, x: float, y: float, width: float, height: float) -> None:
    canvas.drawImage(
        ImageReader(str(qr_path)),
        x,
        y,
        width=width,
        height=height,
        preserveAspectRatio=True,
        mask="auto",
    )


def draw_bullet_list(
    canvas: Canvas,
    items: list[str],
    x: float,
    y_top: float,
    width: float,
    font_name: str,
    font_size: float,
    text_color: colors.Color,
    bullet_color: colors.Color,
    leading: float,
    gap: float = 3.0,
) -> float:
    current_top = y_top
    for item in items:
        canvas.saveState()
        canvas.setFillColor(bullet_color)
        canvas.circle(x + 3, current_top - 8, 1.8, stroke=0, fill=1)
        canvas.restoreState()
        height = draw_paragraph(
            canvas,
            item,
            x + 12,
            current_top,
            width - 12,
            font_name,
            font_size,
            text_color,
            leading=leading,
        )
        current_top -= height + gap
    return current_top


def draw_numbered_list(
    canvas: Canvas,
    items: list[str],
    x: float,
    y_top: float,
    width: float,
    font_name: str,
    font_size: float,
    text_color: colors.Color,
    number_color: colors.Color,
    leading: float,
    gap: float = 3.0,
) -> float:
    current_top = y_top
    for index, item in enumerate(items, start=1):
        canvas.setFillColor(number_color)
        canvas.setFont(font_name, font_size)
        canvas.drawString(x, current_top - 9, f"{index}.")
        height = draw_paragraph(
            canvas,
            item,
            x + 12,
            current_top,
            width - 12,
            font_name,
            font_size,
            text_color,
            leading=leading,
        )
        current_top -= height + gap
    return current_top


def draw_label_value_panel(
    canvas: Canvas,
    x: float,
    y: float,
    width: float,
    height: float,
    radius: float,
    label_width: float,
    fonts: dict[str, str],
    theme: dict[str, colors.Color],
    ssid: str,
    password: str,
    label_font_size: float = 10.5,
    ssid_start_size: int = 20,
    ssid_min_size: int = 12,
    password_start_size: int = 19,
    password_min_size: int = 11,
) -> None:
    row_height = height / 2
    panel_path = canvas.beginPath()
    panel_path.roundRect(x, y, width, height, radius)

    canvas.saveState()
    canvas.setFillColor(theme["panel_background"])
    canvas.drawPath(panel_path, stroke=0, fill=1)
    canvas.clipPath(panel_path, stroke=0, fill=0)
    canvas.setFillColor(theme["label_band"])
    canvas.rect(x, y, label_width, height, fill=1, stroke=0)
    canvas.restoreState()

    canvas.saveState()
    canvas.setStrokeColor(theme["panel_border"])
    canvas.drawPath(panel_path, stroke=1, fill=0)
    canvas.line(x, y + row_height, x + width, y + row_height)
    canvas.line(x + label_width, y, x + label_width, y + height)
    canvas.restoreState()

    canvas.setFillColor(theme["label_text"])
    canvas.setFont(fonts["bold"], label_font_size)
    canvas.drawString(x + 12, y + row_height + 13, LABEL_NETWORK)
    canvas.drawString(x + 12, y + 13, LABEL_PASSWORD)

    ssid_font = fit_font_size(ssid, fonts["bold"], width - label_width - 24, ssid_start_size, ssid_min_size)
    pwd_font = fit_font_size(password, fonts["bold"], width - label_width - 24, password_start_size, password_min_size)
    canvas.setFillColor(theme["value_text"])
    canvas.setFont(fonts["bold"], ssid_font)
    canvas.drawString(x + label_width + 12, y + row_height + 10, ssid)
    canvas.setFont(fonts["bold"], pwd_font)
    canvas.drawString(x + label_width + 12, y + 10, password)


def draw_sheet_layout(
    canvas: Canvas,
    record: WifiRecord,
    building_name: str,
    qr_path: Path,
    settings: Any,
    fonts: dict[str, str],
    theme: dict[str, colors.Color | str],
) -> None:
    page_width, page_height = canvas._pagesize

    canvas.setTitle(f"{building_name} - {record.ssid}")
    canvas.setAuthor(settings.branding.brand_name)
    canvas.setFillColor(theme["page_background"])
    canvas.rect(0, 0, page_width, page_height, fill=1, stroke=0)
    _draw_basic_layout(canvas, record, building_name, qr_path, settings, fonts, theme)


def _draw_basic_layout(
    canvas: Canvas,
    record: WifiRecord,
    building_name: str,
    qr_path: Path,
    settings: Any,
    fonts: dict[str, str],
    theme: dict[str, colors.Color | str],
) -> None:
    page_width, page_height = canvas._pagesize
    margin = 22
    radius = 11
    header_height = 80
    header_bottom = page_height - header_height
    panel_width = page_width - (2 * margin)
    label_width = 186

    canvas.setFillColor(theme["header_background"])
    canvas.rect(0, header_bottom, page_width, header_height, fill=1, stroke=0)
    draw_logo(canvas, settings.branding.logo_path, margin, header_bottom + 31, 144, 26)
    canvas.setFillColor(theme["title_text"])
    canvas.setFont(fonts["bold"], 10.8)
    canvas.drawCentredString(page_width / 2, header_bottom + 58, building_name)
    canvas.setStrokeColor(theme["header_rule"])
    canvas.setLineWidth(1.3)
    canvas.line(margin, header_bottom + 18, page_width - margin, header_bottom + 18)
    draw_card(
        canvas,
        page_width - margin - 96,
        header_bottom - 2,
        96,
        78,
        colors.white,
        10,
        theme["qr_border"],
    )
    draw_qr(canvas, qr_path, page_width - margin - 84, header_bottom + 1, 72, 72)

    info_y = header_bottom - 74
    draw_label_value_panel(
        canvas,
        margin,
        info_y,
        panel_width,
        54,
        radius,
        label_width,
        fonts,
        theme,
        record.ssid,
        record.password or "",
        label_font_size=8.8,
        ssid_start_size=13,
        ssid_min_size=10,
        password_start_size=12,
        password_min_size=9,
    )

    qr_note_y = info_y - 76
    draw_card(canvas, margin, qr_note_y, panel_width, 64, theme["note_background"], 10, theme["panel_border"])
    canvas.setFillColor(theme["note_text"])
    canvas.setFont(fonts["bold"], 9.2)
    canvas.drawString(margin + 12, qr_note_y + 50, "Code QR | QR code")
    draw_paragraph(
        canvas,
        f"{QR_NOTE_FR}<br/>{QR_NOTE_EN}",
        margin + 12,
        qr_note_y + 38,
        panel_width - 24,
        fonts["regular"],
        9.0,
        theme["body_text"],
        leading=9.1,
        bold_fragments=True,
    )

    fr_y = 402
    fr_height = 148
    en_y = 262
    en_height = 126

    draw_card(canvas, margin, fr_y, panel_width, fr_height, theme["section_background"], radius, theme["section_border"])
    draw_card(canvas, margin, en_y, panel_width, en_height, theme["section_background"], radius, theme["section_border"])

    canvas.setFillColor(theme["section_title_text"])
    canvas.setFont(fonts["bold"], 10.8)
    canvas.drawString(margin + 14, fr_y + fr_height - 18, FR_TITLE)
    canvas.drawString(margin + 14, en_y + en_height - 18, EN_TITLE)
    canvas.setStrokeColor(theme["section_border"])
    canvas.setLineWidth(0.9)
    canvas.line(margin + 14, fr_y + fr_height - 24, margin + panel_width - 14, fr_y + fr_height - 24)
    canvas.line(margin + 14, en_y + en_height - 24, margin + panel_width - 14, en_y + en_height - 24)

    draw_bullet_list(
        canvas,
        FR_ITEMS,
        margin + 14,
        fr_y + fr_height - 30,
        panel_width - 28,
        fonts["regular"],
        9.35,
        theme["body_text"],
        theme["bullet"],
        leading=10.1,
        gap=1.5,
    )
    draw_bullet_list(
        canvas,
        EN_ITEMS,
        margin + 14,
        en_y + en_height - 30,
        panel_width - 28,
        fonts["regular"],
        9.45,
        theme["body_text"],
        theme["bullet"],
        leading=10.2,
        gap=1.7,
    )

    note_y = 238
    draw_card(canvas, margin, note_y, panel_width, 22, theme["note_background"], 11)
    canvas.setFillColor(theme["note_text"])
    canvas.setFont(fonts["bold"], 9.55)
    canvas.drawCentredString(margin + (panel_width / 2), note_y + 7, KEEP_LINE)

    support_y = 114
    support_height = 110
    tech_width = 342
    iptv_x = margin + tech_width + 12
    iptv_width = panel_width - tech_width - 12

    draw_card(canvas, margin, support_y, tech_width, support_height, theme["support_background"], radius, theme["support_border"])
    draw_card(canvas, iptv_x, support_y, iptv_width, support_height, theme["support_background"], radius, theme["support_border"])

    draw_paragraph(
        canvas,
        TECH_TITLE,
        margin + 12,
        support_y + support_height - 12,
        tech_width - 24,
        fonts["bold"],
        9.85,
        theme["title_text"],
        leading=10.0,
    )
    draw_numbered_list(
        canvas,
        TECH_ITEMS,
        margin + 12,
        support_y + support_height - 41,
        tech_width - 24,
        fonts["regular"],
        9.6,
        theme["body_text"],
        theme["bullet"],
        leading=10.0,
        gap=1.4,
    )

    draw_paragraph(
        canvas,
        IPTV_TITLE,
        iptv_x + 12,
        support_y + support_height - 12,
        iptv_width - 24,
        fonts["bold"],
        9.65,
        theme["title_text"],
        leading=9.8,
    )
    draw_bullet_list(
        canvas,
        IPTV_ITEMS,
        iptv_x + 12,
        support_y + support_height - 44,
        iptv_width - 24,
        fonts["regular"],
        9.55,
        theme["body_text"],
        theme["bullet"],
        leading=9.9,
        gap=1.4,
    )

    closing_y = 48
    draw_card(canvas, margin, closing_y, panel_width, 24, theme["footer_background"], 11)
    draw_paragraph(
        canvas,
        CLOSING_LINE,
        margin + 12,
        closing_y + 16,
        panel_width - 24,
        fonts["bold"],
        9.15,
        theme["footer_text"],
        leading=9.3,
    )
