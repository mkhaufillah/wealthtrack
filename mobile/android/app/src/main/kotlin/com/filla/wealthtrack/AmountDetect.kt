package com.filla.wealthtrack

/** Keep in sync with bank_parser.parse_amount and BankCapture.parseAmount. */
object AmountDetect {
    private val CURRENCY_BEFORE =
        Regex("(?i)(?:rp\\.?|idr|rupiah|usd|us\\$|\\$)\\s*([0-9][0-9.\\s,]*)")
    private val CURRENCY_AFTER =
        Regex("(?i)([0-9][0-9.\\s,]*)\\s*(?:rp\\.?|idr|rupiah|usd|us\\$|\\$)")
    private val CONTEXT =
        Regex(
            "(?i)(?:debit|kredit|nominal|sebesar|amount|paid|received|transfer|qris|" +
                "bayar|pembelian|pembayaran)\\s*:?\\s*([0-9][0-9.\\s,]*)",
        )
    private val BARE =
        Regex("(?<![0-9.])([1-9][0-9]{0,2}(?:[.,\\s][0-9]{3}){1,4})(?![0-9])")

    fun hasAmount(blob: String): Boolean = parseAmount(blob) != null

    fun parseAmount(blob: String): Int? {
        val text = blob
        for (re in listOf(CURRENCY_BEFORE, CURRENCY_AFTER, CONTEXT, BARE)) {
            for (m in re.findAll(text)) {
                val end = m.range.last + 1
                if (end < text.length && text[end] == '%') continue
                val v = normalizeNumber(m.groupValues[1])
                if (v != null) return v
            }
        }
        return null
    }

    private fun normalizeNumber(raw: String): Int? {
        var s = raw.replace("\u00a0", " ").trim()
        s = s.replace(Regex(",-+$"), "")
        s = s.replace(" ", "")
        if (s.isEmpty() || !s.any { it.isDigit() }) return null
        if (s[0] == '0') return null
        if (s.contains(',') && s.contains('.')) {
            s = if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
                s.substringBefore(',').replace(".", "")
            } else {
                s.substringBefore('.').replace(",", "")
            }
        } else if (s.contains(',')) {
            val parts = s.split(',')
            s = if (parts.size == 2 && parts[1].length in 1..2) parts[0] else s.replace(",", "")
        } else if (s.contains('.')) {
            val parts = s.split('.')
            s = if (parts.size == 2 && parts[1].length in 1..2) parts[0] else s.replace(".", "")
        }
        val value = s.toLongOrNull() ?: return null
        if (value <= 0L || value > 10_000_000_000L) return null
        return value.toInt()
    }
}
