import 'package:flutter/material.dart';

import '../../../core/db/enums.dart';

IconData tradeIcon(Trade trade) => switch (trade) {
      Trade.electrical => Icons.electrical_services,
      Trade.plumbing => Icons.plumbing,
      Trade.civil => Icons.foundation,
      Trade.painting => Icons.format_paint,
      Trade.tiles => Icons.grid_on,
      Trade.carpentry => Icons.carpenter,
      Trade.pop => Icons.roofing,
      Trade.fabrication => Icons.hardware,
      Trade.labourSupply => Icons.groups,
      Trade.other => Icons.more_horiz,
    };
