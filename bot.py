import logging
from datetime import time
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application, CommandHandler, CallbackQueryHandler, ContextTypes
)

TOKEN = "8267904285:AAGVOoTasLqP8dGr82euRFSxyw34wuGnSCs"
CHAT_ID = 90437191

GAMEIA_1 = {
    "data": {
        "2025-08": {"name": "العطار ربيع المتحدة", "note": ""},
        "2025-09": {"name": "المقدس سعد / أم القري", "note": "نص سهم"},
        "2025-10": {"name": "أحمد عبد الفتاح", "note": ""},
        "2025-11": {"name": "العطار ربيع المتحدة", "note": ""},
        "2025-12": {"name": "العطار ربيع المتحدة", "note": ""},
        "2026-01": {"name": "العطار ربيع المتحدة", "note": ""},
        "2026-02": {"name": "عيد سعد", "note": ""},
        "2026-03": {"name": "المقدس سعد / أم القري", "note": ""},
        "2026-04": {"name": "العطار ربيع المتحدة", "note": "تم التأكيد"},
        "2026-05": {"name": "د. ربيع", "note": ""},
        "2026-06": {"name": "ياسر حجاج", "note": ""},
        "2026-07": {"name": "سيد العديسات", "note": ""},
        "2026-08": {"name": "محمد حسب الله", "note": ""},
        "2026-09": {"name": "عيد سعد / محمد حسباللة", "note": "نص سهم لكل"},
        "2026-10": {"name": "؟", "note": "غير محدد"},
        "2026-11": {"name": "ربيع / الزاوية الحمراء", "note": ""},
        "2026-12": {"name": "ربيع", "note": ""},
        "2027-01": {"name": "ربيع", "note": ""},
        "2027-02": {"name": "ربيع", "note": ""},
        "2027-03": {"name": "ربيع", "note": ""},
        "2027-04": {"name": "ربيع / أبو رضوي", "note": ""},
    }
}

GAMEIA_2 = {
    "data": {
        1:  {"name": "الأمين", "note": "1-10"},
        2:  {"name": "ربيع", "note": "الأخير"},
        3:  {"name": "رضوي", "note": "24"},
        4:  {"name": "كيان", "note": "23"},
        5:  {"name": "أبو رضوي", "note": "22"},
        6:  {"name": "خالد", "note": "21"},
        7:  {"name": "كيان", "note": "20 - تم التأكيد"},
        8:  {"name": "الزاوية الحمراء", "note": "19"},
        9:  {"name": "أبو رضوي", "note": "18"},
        10: {"name": "أبو رضوي", "note": "17"},
        11: {"name": "المتحدة", "note": "تم التأكيد"},
        12: {"name": "الزاوية الحمراء", "note": ""},
        13: {"name": "الزاوية الحمراء", "note": ""},
        14: {"name": "ربيع / الزاوية", "note": ""},
        15: {"name": "ربيع", "note": ""},
        16: {"name": "ربيع", "note": ""},
        17: {"name": "ربيع / المتحدة", "note": ""},
        18: {"name": "ربيع / المتحدة", "note": ""},
        19: {"name": "ربيع / أبو رضوي", "note": ""},
        20: {"name": "كيان", "note": ""},
        21: {"name": "فاضي", "note": ""},
        22: {"name": "أبو رضوي", "note": ""},
        23: {"name": "كيان", "note": ""},
        24: {"name": "أبو رضوي", "note": ""},
        25: {"name": "ربيع", "note": "10-27"},
    }
}

def get_current_month_key():
    from datetime import datetime
    now = datetime.now()
    return f"{now.year}-{now.month:02d}"

def build_monthly_message():
    from datetime import datetime
    now = datetime.now()
    month_names = {1:"يناير",2:"فبراير",3:"مارس",4:"أبريل",5:"مايو",6:"يونيو",7:"يوليو",8:"أغسطس",9:"سبتمبر",10:"أكتوبر",11:"نوفمبر",12:"ديسمبر"}
    key = get_current_month_key()
    msg = f"📅 *تذكير الجمعية - {month_names[now.month]} {now.year}*\n━━━━━━━━━━━━━━━━━━\n\n"
    g1 = GAMEIA_1["data"].get(key)
    msg += "🏦 *الجمعية الأولى* (400,000 جنيه)\n"
    if g1:
        msg += f"👤 القابض: *{g1['name']}*\n"
        if g1['note']:
            msg += f"📌 ملاحظة: {g1['note']}\n"
    else:
        msg += "❓ مش محدد القابض لهذا الشهر\n"
    msg += "\n━━━━━━━━━━━━━━━━━━\n💰 *الجمعية الثانية* - راجع /gameia2\n"
    return msg

def main_keyboard():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("📅 الشهر ده مين هيقبض؟", callback_data="this_month")],
        [InlineKeyboardButton("📋 جدول الجمعية الأولى", callback_data="gameia1_full")],
        [InlineKeyboardButton("📋 جدول الجمعية الثانية", callback_data="gameia2_full")],
    ])

def back_keyboard():
    return InlineKeyboardMarkup([[InlineKeyboardButton("🔙 رجوع", callback_data="main_menu")]])

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("🎯 *بوت الجمعيات - جمعيا*\n\nاختار اللي تعايزه:", reply_markup=main_keyboard(), parse_mode="Markdown")

async def this_month_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(build_monthly_message(), parse_mode="Markdown", reply_markup=back_keyboard())

async def gameia1_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    current_key = get_current_month_key()
    msg = "🏦 *جدول الجمعية الأولى*\n400,000 جنيه شهرياً\n━━━━━━━━━━━━━━━━━━\n"
    for k, v in GAMEIA_1["data"].items():
        m = "◀️ " if k == current_key else ""
        n = f" ({v['note']})" if v['note'] else ""
        msg += f"{m}`{k}` — {v['name']}{n}\n"
    await update.message.reply_text(msg, parse_mode="Markdown")

async def gameia2_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    msg = "💰 *جدول الجمعية الثانية*\n625,000 جنيه للسهم\n━━━━━━━━━━━━━━━━━━\n"
    for num, v in GAMEIA_2["data"].items():
        n = f" ({v['note']})" if v['note'] else ""
        msg += f"السهم {num}: *{v['name']}*{n}\n"
    await update.message.reply_text(msg, parse_mode="Markdown")

async def button_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    d = query.data

    if d == "main_menu":
        await query.edit_message_text("🎯 *بوت الجمعيات - جمعيا*\n\nاختار اللي تعايزه:", reply_markup=main_keyboard(), parse_mode="Markdown")

    elif d == "this_month":
        await query.edit_message_text(build_monthly_message(), parse_mode="Markdown", reply_markup=back_keyboard())

    elif d == "gameia1_full":
        current_key = get_current_month_key()
        msg = "🏦 *جدول الجمعية الأولى*\n400,000 جنيه شهرياً\n━━━━━━━━━━━━━━━━━━\n"
        for k, v in GAMEIA_1["data"].items():
            m = "◀️ " if k == current_key else ""
            n = f" ({v['note']})" if v['note'] else ""
            msg += f"{m}`{k}` — {v['name']}{n}\n"
        await query.edit_message_text(msg, parse_mode="Markdown", reply_markup=back_keyboard())

    elif d == "gameia2_full":
        msg = "💰 *جدول الجمعية الثانية*\n625,000 جنيه للسهم\n━━━━━━━━━━━━━━━━━━\n"
        for num, v in GAMEIA_2["data"].items():
            n = f" ({v['note']})" if v['note'] else ""
            msg += f"السهم {num}: *{v['name']}*{n}\n"
        await query.edit_message_text(msg, parse_mode="Markdown", reply_markup=back_keyboard())

async def monthly_reminder(context: ContextTypes.DEFAULT_TYPE):
    await context.bot.send_message(chat_id=CHAT_ID, text=build_monthly_message(), parse_mode="Markdown")

def main():
    logging.basicConfig(level=logging.INFO)
    app = Application.builder().token(TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("thismonth", this_month_command))
    app.add_handler(CommandHandler("gameia1", gameia1_command))
    app.add_handler(CommandHandler("gameia2", gameia2_command))
    app.add_handler(CallbackQueryHandler(button_handler))
    app.job_queue.run_monthly(monthly_reminder, when=time(9, 0), day=1)
    print("✅ البوت شغال!")
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()
