import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Gradient header with soft rounded bottom — Linear / Notion mobile style.
class ModernAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ModernAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.gradient,
  });

  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final Gradient? gradient;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: leading,
      actions: actions,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      centerTitle: false,
      title: Text(
        title,
        style: AppTheme.headlineSmall.copyWith(color: Colors.white),
      ),
      flexibleSpace: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        child: Container(
          decoration: BoxDecoration(
            gradient: gradient ?? AppTheme.brandGradient,
            boxShadow: AppTheme.softShadow,
          ),
        ),
      ),
      bottom: bottom,
    );
  }
}

/// Floating glass bottom navigation — 2025+ mobile SaaS pattern.
class ModernBottomNav extends StatelessWidget {
  const ModernBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<ModernNavItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
              boxShadow: AppTheme.elevatedShadow,
            ),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _NavItemButton(
                      item: items[i],
                      selected: selectedIndex == i,
                      onTap: () => onSelected(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ModernNavItem {
  const ModernNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Color color;
}

class _NavItemButton extends StatelessWidget {
  const _NavItemButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ModernNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? item.color.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? item.selectedIcon : item.icon,
                size: 22,
                color: selected ? item.color : AppTheme.muted,
              ),
              const SizedBox(height: 2),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? item.color : AppTheme.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact bento-style stat tile for dashboard grids (mobile essentials).
class BentoStatCard extends StatelessWidget {
  const BentoStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
    this.hint,
    this.highlight = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String? hint;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white,
            boxShadow: AppTheme.cardShadow,
            border: Border.all(
              color: highlight
                  ? color.withValues(alpha: 0.35)
                  : AppTheme.border.withValues(alpha: 0.9),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppIconBadge(icon: icon, color: color, size: 34, iconSize: 18),
                  const Spacer(),
                  if (highlight)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.displaySmall.copyWith(
                  color: AppTheme.primary,
                  fontSize: 22,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.labelMedium.copyWith(
                  color: AppTheme.muted,
                  fontSize: 11,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 2),
                Text(
                  hint!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodySmall.copyWith(
                    fontSize: 10,
                    color: highlight ? color : AppTheme.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.color,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [c, c.withValues(alpha: 0.4)],
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.titleMedium.copyWith(fontSize: 15)),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.muted),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Modern list row — soft shadow card, colored icon tile.
class ModernListCard extends StatelessWidget {
  const ModernListCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.icon,
    this.color,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        elevation: 0,
        shadowColor: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: AppTheme.cardShadow,
              border: Border.all(color: AppTheme.border.withValues(alpha: 0.6)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: icon != null
                  ? AppIconBadge(icon: icon!, color: c, size: 44, iconSize: 22)
                  : null,
              title: Text(title, style: AppTheme.titleSmall),
              subtitle: subtitle != null
                  ? Text(subtitle!, style: AppTheme.bodySmall)
                  : null,
              trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: AppTheme.muted),
            ),
          ),
        ),
      ),
    );
  }
}
