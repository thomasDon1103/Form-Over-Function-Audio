import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../genre_color_utils.dart';

class LibrarySidebar extends StatelessWidget {
  const LibrarySidebar({
    super.key,
    required this.genres,
    required this.selectedGenre,
    required this.albumCount,
    required this.visibleAlbumCount,
    required this.genreColors,
    required this.onGenreSelected,
    required this.onGenreColorSelected,
    required this.onAddGenre,
    required this.onRemoveSelectedGenre,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final List<String> genres;
  final String? selectedGenre;
  final int albumCount;
  final int visibleAlbumCount;
  final Map<String, String> genreColors;
  final ValueChanged<String?> onGenreSelected;
  final ValueChanged<String> onGenreColorSelected;
  final VoidCallback onAddGenre;
  final VoidCallback onRemoveSelectedGenre;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;

    return Material(
      color: collection.panelStrong.withValues(alpha: 0.82),
      elevation: 10,
      shadowColor: collection.glow.withValues(alpha: 0.12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        width: collapsed ? 70 : 288,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showExpanded = !collapsed && constraints.maxWidth >= 260;
            return ClipRect(
              child: showExpanded
                  ? _ExpandedSidebar(
                      genres: genres,
                      selectedGenre: selectedGenre,
                      albumCount: albumCount,
                      visibleAlbumCount: visibleAlbumCount,
                      genreColors: genreColors,
                      onGenreSelected: onGenreSelected,
                      onGenreColorSelected: onGenreColorSelected,
                      onAddGenre: onAddGenre,
                      onRemoveSelectedGenre: onRemoveSelectedGenre,
                      onToggleCollapsed: onToggleCollapsed,
                    )
                  : _CollapsedSidebar(onToggleCollapsed: onToggleCollapsed),
            );
          },
        ),
      ),
    );
  }
}

class _ExpandedSidebar extends StatelessWidget {
  const _ExpandedSidebar({
    required this.genres,
    required this.selectedGenre,
    required this.albumCount,
    required this.visibleAlbumCount,
    required this.genreColors,
    required this.onGenreSelected,
    required this.onGenreColorSelected,
    required this.onAddGenre,
    required this.onRemoveSelectedGenre,
    required this.onToggleCollapsed,
  });

  final List<String> genres;
  final String? selectedGenre;
  final int albumCount;
  final int visibleAlbumCount;
  final Map<String, String> genreColors;
  final ValueChanged<String?> onGenreSelected;
  final ValueChanged<String> onGenreColorSelected;
  final VoidCallback onAddGenre;
  final VoidCallback onRemoveSelectedGenre;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final defaultGenreColor = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SidebarHeader(
            visibleAlbumCount: visibleAlbumCount,
            albumCount: albumCount,
            onToggleCollapsed: onToggleCollapsed,
          ),
          const SizedBox(height: 16),
          Text('Genres', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _GenreFilterButton(
            label: 'All Albums',
            selected: selectedGenre == null,
            onTap: () => onGenreSelected(null),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(right: 18),
              itemCount: genres.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final genre = genres[index];
                return Row(
                  children: [
                    Expanded(
                      child: _GenreFilterButton(
                        label: genre,
                        selected: selectedGenre == genre,
                        onTap: () => onGenreSelected(genre),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _GenreColorButton(
                      color: genreColorFor(
                        genre,
                        genreColors,
                        defaultGenreColor,
                      ),
                      onTap: () => onGenreColorSelected(genre),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _SidebarActionButton(
            onPressed: onAddGenre,
            icon: Icons.add,
            label: 'Add Genre',
          ),
          const SizedBox(height: 8),
          _SidebarActionButton(
            onPressed: selectedGenre == null ? null : onRemoveSelectedGenre,
            icon: Icons.delete_outline,
            label: 'Remove Genre',
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 14),
          Divider(color: collection.panelBorder),
          const SizedBox(height: 10),
          Text('Options', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
        ],
      ),
    );
  }
}

class _CollapsedSidebar extends StatelessWidget {
  const _CollapsedSidebar({required this.onToggleCollapsed});

  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Column(
        children: [
          Icon(Icons.tune, color: colorScheme.primary),
          const SizedBox(height: 12),
          _SidebarChromeButton(
            onPressed: onToggleCollapsed,
            icon: const Icon(Icons.chevron_right),
            collection: collection,
          ),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.visibleAlbumCount,
    required this.albumCount,
    required this.onToggleCollapsed,
  });

  final int visibleAlbumCount;
  final int albumCount;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.tune, color: colorScheme.primary),
              const SizedBox(height: 10),
              Text('Library', style: textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '$visibleAlbumCount of $albumCount albums',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        _SidebarChromeButton(
          onPressed: onToggleCollapsed,
          icon: const Icon(Icons.chevron_left),
          collection: collection,
        ),
      ],
    );
  }
}

class _SidebarChromeButton extends StatelessWidget {
  const _SidebarChromeButton({
    required this.onPressed,
    required this.icon,
    required this.collection,
  });

  final VoidCallback onPressed;
  final Widget icon;
  final CollectionTheme collection;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return IconButton.filledTonal(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: collection.glow.withValues(alpha: 0.18),
        foregroundColor: colorScheme.primary,
        hoverColor: collection.glow.withValues(alpha: 0.28),
        side: BorderSide(color: collection.panelBorder),
      ),
      icon: icon,
    );
  }
}

class _SidebarActionButton extends StatelessWidget {
  const _SidebarActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.foregroundColor,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(foregroundColor: foregroundColor),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _GenreColorButton extends StatelessWidget {
  const _GenreColorButton({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: collection.panelBorder),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.28),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _GenreFilterButton extends StatelessWidget {
  const _GenreFilterButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.18)
            : collection.panel.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? colorScheme.primary : collection.panelBorder,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.circle_outlined,
                size: 16,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
