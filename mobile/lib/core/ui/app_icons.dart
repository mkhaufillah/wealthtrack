import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

/// Hugeicons stroke-rounded. Never use Material [Icons] in product UI.
class AppIcons {
  static const home = HugeIcons.strokeRoundedHome01;
  static const wallet = HugeIcons.strokeRoundedWallet01;
  static const receipt = HugeIcons.strokeRoundedInvoice01;
  static const chart = HugeIcons.strokeRoundedChartHistogram;
  static const user = HugeIcons.strokeRoundedUser;
  static const add = HugeIcons.strokeRoundedAdd01;
  static const back = HugeIcons.strokeRoundedArrowLeft01;
  static const next = HugeIcons.strokeRoundedArrowRight01;
  static const search = HugeIcons.strokeRoundedSearch01;
  static const camera = HugeIcons.strokeRoundedCamera01;
  static const gallery = HugeIcons.strokeRoundedImage01;
  static const trash = HugeIcons.strokeRoundedDelete02;
  static const alert = HugeIcons.strokeRoundedAlert02;
  static const close = HugeIcons.strokeRoundedCancel01;
  static const refresh = HugeIcons.strokeRoundedRefresh;
  static const piggy = HugeIcons.strokeRoundedPiggyBank;
  static const shield = HugeIcons.strokeRoundedShield01;
  static const ai = HugeIcons.strokeRoundedAiBrain01;
  static const bank = HugeIcons.strokeRoundedBank;
  static const house = HugeIcons.strokeRoundedHouse01;
  static const calendar = HugeIcons.strokeRoundedCalendar01;
  static const edit = HugeIcons.strokeRoundedPencilEdit01;
  static const logout = HugeIcons.strokeRoundedLogout01;
  static const settings = HugeIcons.strokeRoundedSettings01;
  static const view = HugeIcons.strokeRoundedView;
  static const viewOff = HugeIcons.strokeRoundedViewOffSlash;
  static const swap = HugeIcons.strokeRoundedExchange01;
  static const send = HugeIcons.strokeRoundedSent;
  static const info = HugeIcons.strokeRoundedInformationCircle;
  static const card = HugeIcons.strokeRoundedCreditCard;
  static const money = HugeIcons.strokeRoundedMoneyBag01;
  static const filter = HugeIcons.strokeRoundedFilter;
  static const more = HugeIcons.strokeRoundedMoreVertical;
  static const check = HugeIcons.strokeRoundedCheckmarkCircle01;
  static const inbox = HugeIcons.strokeRoundedInbox;
  static const spark = HugeIcons.strokeRoundedSparkles;
  static const chartUp = HugeIcons.strokeRoundedAnalyticsUp;
}

class AppIcon extends StatelessWidget {
  final List<List<dynamic>> icon;
  final double size;
  final Color? color;
  const AppIcon(this.icon, {super.key, this.size = 22, this.color});

  @override
  Widget build(BuildContext context) {
    final resolved = color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    return HugeIcon(
      icon: icon,
      size: size,
      color: resolved,
    );
  }
}
