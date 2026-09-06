/// ID copy fallback until GET /ui/bootstrap (Phase 1).
const Map<String, String> copyFallback = {
  'home.hero_title': 'Uang kamu',
  'home.income': 'Masuk',
  'home.expense': 'Keluar',
  'nav.dashboard': 'Beranda',
  'nav.transactions': 'Transaksi',
  'nav.budgets': 'Anggaran',
  'nav.reports': 'Laporan',
  'nav.profile': 'Profil',
};

String t(String key) => copyFallback[key] ?? key;
