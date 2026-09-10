import 'package:flutter/material.dart';

/// WhatsApp-style avatar picker with emoji/icon-based avatars.
///
/// Returns the selected avatar key (e.g. 'avatar_1') or null if dismissed.
class AvatarPickerSheet extends StatefulWidget {
  const AvatarPickerSheet({super.key, this.currentAvatar});

  final String? currentAvatar;

  /// Show the avatar picker and return the selected key.
  static Future<String?> show(BuildContext context, {String? currentAvatar}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AvatarPickerSheet(currentAvatar: currentAvatar),
    );
  }

  @override
  State<AvatarPickerSheet> createState() => _AvatarPickerSheetState();
}

class _AvatarPickerSheetState extends State<AvatarPickerSheet> {
  late String? _selected;
  String _selectedCategory = 'All';

  static const _categories = [
    'All',
    'Faces',
    'Skilled',
    'Animals',
    'Nature',
    'Activities',
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.currentAvatar;
  }

  List<AvatarOption> get _filteredOptions {
    if (_selectedCategory == 'All') return avatarOptions;
    return avatarOptions.where((a) => a.category == _selectedCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.face_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Choose Avatar',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_selected != null)
                  TextButton(
                    onPressed: () => Navigator.pop(context, 'remove_avatar'),
                    child: const Text('Remove',
                        style: TextStyle(color: Colors.red)),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Category chips
          SizedBox(
            height: 38,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final cat = _categories[idx];
                final isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  selectedColor: const Color(0xFF6A11CB).withValues(alpha: 0.15),
                  backgroundColor: Colors.grey[100],
                  labelStyle: TextStyle(
                    color: isSelected
                        ? const Color(0xFF6A11CB)
                        : const Color(0xFF475569),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 12.5,
                  ),
                  side: BorderSide(
                    color: isSelected
                        ? const Color(0xFF6A11CB)
                        : Colors.transparent,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedCategory = cat);
                    }
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          // Avatar grid
          Flexible(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 1,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _filteredOptions.length,
              itemBuilder: (context, index) {
                final avatar = _filteredOptions[index];
                final isSelected = _selected == avatar.key;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selected = avatar.key);
                    Navigator.pop(context, avatar.key);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? avatar.bgColor.withValues(alpha: 0.3)
                          : avatar.bgColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF6A11CB)
                            : Colors.grey[200]!,
                        width: isSelected ? 2.5 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: const Color(0xFF6A11CB)
                                    .withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : [],
                    ),
                    child: Center(
                      child: Text(
                        avatar.emoji,
                        style: const TextStyle(fontSize: 34),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// An avatar option with a key, emoji, background color, and category.
class AvatarOption {
  const AvatarOption({
    required this.key,
    required this.emoji,
    required this.bgColor,
    this.category = 'Faces',
  });
  final String key;
  final String emoji;
  final Color bgColor;
  final String category;
}

/// All available avatar options with rich selection
const avatarOptions = <AvatarOption>[
  // ── Faces & People ──
  AvatarOption(key: 'avatar_smile', emoji: '😊', bgColor: Color(0xFFFFF9C4), category: 'Faces'),
  AvatarOption(key: 'avatar_cool', emoji: '😎', bgColor: Color(0xFFBBDEFB), category: 'Faces'),
  AvatarOption(key: 'avatar_nerd', emoji: '🤓', bgColor: Color(0xFFC8E6C9), category: 'Faces'),
  AvatarOption(key: 'avatar_wink', emoji: '😉', bgColor: Color(0xFFFFF9C4), category: 'Faces'),
  AvatarOption(key: 'avatar_star', emoji: '🤩', bgColor: Color(0xFFFFE0B2), category: 'Faces'),
  AvatarOption(key: 'avatar_think', emoji: '🤔', bgColor: Color(0xFFE1BEE7), category: 'Faces'),
  AvatarOption(key: 'avatar_heart', emoji: '🥰', bgColor: Color(0xFFF8BBD0), category: 'Faces'),
  AvatarOption(key: 'avatar_laugh', emoji: '😂', bgColor: Color(0xFFFFF9C4), category: 'Faces'),
  AvatarOption(key: 'avatar_party', emoji: '🥳', bgColor: Color(0xFFFFE0B2), category: 'Faces'),
  AvatarOption(key: 'avatar_halo', emoji: '😇', bgColor: Color(0xFFE1F5FE), category: 'Faces'),
  AvatarOption(key: 'avatar_cowboy', emoji: '🤠', bgColor: Color(0xFFD7CCC8), category: 'Faces'),
  AvatarOption(key: 'avatar_monocle', emoji: '🧐', bgColor: Color(0xFFE8F5E9), category: 'Faces'),
  AvatarOption(key: 'avatar_disguise', emoji: '🥸', bgColor: Color(0xFFFFF3E0), category: 'Faces'),
  AvatarOption(key: 'avatar_calm', emoji: '😌', bgColor: Color(0xFFE8EAF6), category: 'Faces'),
  AvatarOption(key: 'avatar_robot', emoji: '🤖', bgColor: Color(0xFFCFD8DC), category: 'Faces'),
  AvatarOption(key: 'avatar_alien', emoji: '👽', bgColor: Color(0xFFC8E6C9), category: 'Faces'),
  AvatarOption(key: 'avatar_ghost', emoji: '👻', bgColor: Color(0xFFEDE7F6), category: 'Faces'),
  AvatarOption(key: 'avatar_monster', emoji: '👾', bgColor: Color(0xFFE1BEE7), category: 'Faces'),
  AvatarOption(key: 'avatar_pumpkin', emoji: '🎃', bgColor: Color(0xFFFFE0B2), category: 'Faces'),
  AvatarOption(key: 'avatar_crown', emoji: '👑', bgColor: Color(0xFFFFF9C4), category: 'Faces'),

  // ── Skilled & Professionals ──
  AvatarOption(key: 'avatar_worker', emoji: '👷', bgColor: Color(0xFFFFE0B2), category: 'Skilled'),
  AvatarOption(key: 'avatar_artist', emoji: '🧑‍🎨', bgColor: Color(0xFFE1BEE7), category: 'Skilled'),
  AvatarOption(key: 'avatar_chef', emoji: '👨‍🍳', bgColor: Color(0xFFFFF9C4), category: 'Skilled'),
  AvatarOption(key: 'avatar_tech', emoji: '👨‍💻', bgColor: Color(0xFFBBDEFB), category: 'Skilled'),
  AvatarOption(key: 'avatar_tech_f', emoji: '👩‍💻', bgColor: Color(0xFFE1BEE7), category: 'Skilled'),
  AvatarOption(key: 'avatar_camera', emoji: '📷', bgColor: Color(0xFFB2DFDB), category: 'Skilled'),
  AvatarOption(key: 'avatar_teacher', emoji: '👩‍🏫', bgColor: Color(0xFFC8E6C9), category: 'Skilled'),
  AvatarOption(key: 'avatar_mechanic', emoji: '🔧', bgColor: Color(0xFFCFD8DC), category: 'Skilled'),
  AvatarOption(key: 'avatar_scientist', emoji: '🧑‍🔬', bgColor: Color(0xFFBBDEFB), category: 'Skilled'),
  AvatarOption(key: 'avatar_hammer', emoji: '🔨', bgColor: Color(0xFFFFE0B2), category: 'Skilled'),
  AvatarOption(key: 'avatar_toolbox', emoji: '🧰', bgColor: Color(0xFFFFCDD2), category: 'Skilled'),
  AvatarOption(key: 'avatar_tools', emoji: '🛠️', bgColor: Color(0xFFCFD8DC), category: 'Skilled'),
  AvatarOption(key: 'avatar_palette', emoji: '🎨', bgColor: Color(0xFFF3E5F5), category: 'Skilled'),
  AvatarOption(key: 'avatar_briefcase', emoji: '💼', bgColor: Color(0xFFD7CCC8), category: 'Skilled'),
  AvatarOption(key: 'avatar_microscope', emoji: '🔬', bgColor: Color(0xFFE0F2F1), category: 'Skilled'),
  AvatarOption(key: 'avatar_ruler', emoji: '📐', bgColor: Color(0xFFFFF9C4), category: 'Skilled'),
  AvatarOption(key: 'avatar_scissors', emoji: '✂️', bgColor: Color(0xFFE8EAF6), category: 'Skilled'),
  AvatarOption(key: 'avatar_thread', emoji: '🧵', bgColor: Color(0xFFFFEBEE), category: 'Skilled'),
  AvatarOption(key: 'avatar_farmer', emoji: '🧑‍🌾', bgColor: Color(0xFFDCEDC8), category: 'Skilled'),
  AvatarOption(key: 'avatar_plant_pot', emoji: '🪴', bgColor: Color(0xFFC8E6C9), category: 'Skilled'),
  AvatarOption(key: 'avatar_barber', emoji: '💈', bgColor: Color(0xFFE1F5FE), category: 'Skilled'),

  // ── Animals ──
  AvatarOption(key: 'avatar_cat', emoji: '🐱', bgColor: Color(0xFFFFE0B2), category: 'Animals'),
  AvatarOption(key: 'avatar_dog', emoji: '🐶', bgColor: Color(0xFFD7CCC8), category: 'Animals'),
  AvatarOption(key: 'avatar_fox', emoji: '🦊', bgColor: Color(0xFFFFE0B2), category: 'Animals'),
  AvatarOption(key: 'avatar_panda', emoji: '🐼', bgColor: Color(0xFFE0E0E0), category: 'Animals'),
  AvatarOption(key: 'avatar_lion', emoji: '🦁', bgColor: Color(0xFFFFF9C4), category: 'Animals'),
  AvatarOption(key: 'avatar_tiger', emoji: '🐯', bgColor: Color(0xFFFFE0B2), category: 'Animals'),
  AvatarOption(key: 'avatar_koala', emoji: '🐨', bgColor: Color(0xFFCFD8DC), category: 'Animals'),
  AvatarOption(key: 'avatar_bunny', emoji: '🐰', bgColor: Color(0xFFFCE4EC), category: 'Animals'),
  AvatarOption(key: 'avatar_unicorn', emoji: '🦄', bgColor: Color(0xFFF3E5F5), category: 'Animals'),
  AvatarOption(key: 'avatar_owl', emoji: '🦉', bgColor: Color(0xFFD7CCC8), category: 'Animals'),
  AvatarOption(key: 'avatar_eagle', emoji: '🦅', bgColor: Color(0xFFBBDEFB), category: 'Animals'),
  AvatarOption(key: 'avatar_dolphin', emoji: '🐬', bgColor: Color(0xFFB3E5FC), category: 'Animals'),
  AvatarOption(key: 'avatar_octopus', emoji: '🐙', bgColor: Color(0xFFFFCDD2), category: 'Animals'),
  AvatarOption(key: 'avatar_butterfly', emoji: '🦋', bgColor: Color(0xFFE1BEE7), category: 'Animals'),
  AvatarOption(key: 'avatar_bee', emoji: '🐝', bgColor: Color(0xFFFFF9C4), category: 'Animals'),
  AvatarOption(key: 'avatar_turtle', emoji: '🐢', bgColor: Color(0xFFC8E6C9), category: 'Animals'),
  AvatarOption(key: 'avatar_dino', emoji: '🦖', bgColor: Color(0xFFDCEDC8), category: 'Animals'),
  AvatarOption(key: 'avatar_peacock', emoji: '🦚', bgColor: Color(0xFFB2DFDB), category: 'Animals'),
  AvatarOption(key: 'avatar_elephant', emoji: '🐘', bgColor: Color(0xFFCFD8DC), category: 'Animals'),
  AvatarOption(key: 'avatar_monkey', emoji: '🐵', bgColor: Color(0xFFFFE0B2), category: 'Animals'),

  // ── Nature & Plants ──
  AvatarOption(key: 'avatar_cherry_blossom', emoji: '🌸', bgColor: Color(0xFFFCE4EC), category: 'Nature'),
  AvatarOption(key: 'avatar_hibiscus', emoji: '🌺', bgColor: Color(0xFFFFCDD2), category: 'Nature'),
  AvatarOption(key: 'avatar_sunflower', emoji: '🌻', bgColor: Color(0xFFFFF9C4), category: 'Nature'),
  AvatarOption(key: 'avatar_rose', emoji: '🌹', bgColor: Color(0xFFFFCDD2), category: 'Nature'),
  AvatarOption(key: 'avatar_clover', emoji: '🍀', bgColor: Color(0xFFC8E6C9), category: 'Nature'),
  AvatarOption(key: 'avatar_palm', emoji: '🌴', bgColor: Color(0xFFDCEDC8), category: 'Nature'),
  AvatarOption(key: 'avatar_tree', emoji: '🌲', bgColor: Color(0xFFC8E6C9), category: 'Nature'),
  AvatarOption(key: 'avatar_cactus', emoji: '🌵', bgColor: Color(0xFFDCEDC8), category: 'Nature'),
  AvatarOption(key: 'avatar_herb', emoji: '🌿', bgColor: Color(0xFFE8F5E9), category: 'Nature'),
  AvatarOption(key: 'avatar_maple', emoji: '🍁', bgColor: Color(0xFFFFE0B2), category: 'Nature'),
  AvatarOption(key: 'avatar_mushroom', emoji: '🍄', bgColor: Color(0xFFFFCDD2), category: 'Nature'),
  AvatarOption(key: 'avatar_rainbow', emoji: '🌈', bgColor: Color(0xFFE1F5FE), category: 'Nature'),
  AvatarOption(key: 'avatar_thunder', emoji: '⚡', bgColor: Color(0xFFFFF9C4), category: 'Nature'),
  AvatarOption(key: 'avatar_star_nature', emoji: '⭐', bgColor: Color(0xFFFFF9C4), category: 'Nature'),
  AvatarOption(key: 'avatar_moon', emoji: '🌙', bgColor: Color(0xFFEDE7F6), category: 'Nature'),
  AvatarOption(key: 'avatar_sun', emoji: '☀️', bgColor: Color(0xFFFFF9C4), category: 'Nature'),
  AvatarOption(key: 'avatar_wave', emoji: '🌊', bgColor: Color(0xFFB3E5FC), category: 'Nature'),
  AvatarOption(key: 'avatar_globe', emoji: '🌍', bgColor: Color(0xFFC8E6C9), category: 'Nature'),

  // ── Activities & Fun ──
  AvatarOption(key: 'avatar_rocket', emoji: '🚀', bgColor: Color(0xFFBBDEFB), category: 'Activities'),
  AvatarOption(key: 'avatar_fire', emoji: '🔥', bgColor: Color(0xFFFFCDD2), category: 'Activities'),
  AvatarOption(key: 'avatar_diamond', emoji: '💎', bgColor: Color(0xFFB3E5FC), category: 'Activities'),
  AvatarOption(key: 'avatar_trophy', emoji: '🏆', bgColor: Color(0xFFFFF9C4), category: 'Activities'),
  AvatarOption(key: 'avatar_medal', emoji: '🥇', bgColor: Color(0xFFFFE0B2), category: 'Activities'),
  AvatarOption(key: 'avatar_music', emoji: '🎵', bgColor: Color(0xFFE1BEE7), category: 'Activities'),
  AvatarOption(key: 'avatar_headphones', emoji: '🎧', bgColor: Color(0xFFEDE7F6), category: 'Activities'),
  AvatarOption(key: 'avatar_guitar', emoji: '🎸', bgColor: Color(0xFFFFE0B2), category: 'Activities'),
  AvatarOption(key: 'avatar_game', emoji: '🎮', bgColor: Color(0xFFE1BEE7), category: 'Activities'),
  AvatarOption(key: 'avatar_target', emoji: '🎯', bgColor: Color(0xFFFFCDD2), category: 'Activities'),
  AvatarOption(key: 'avatar_soccer', emoji: '⚽', bgColor: Color(0xFFE0E0E0), category: 'Activities'),
  AvatarOption(key: 'avatar_basketball', emoji: '🏀', bgColor: Color(0xFFFFE0B2), category: 'Activities'),
  AvatarOption(key: 'avatar_bike', emoji: '🚲', bgColor: Color(0xFFE8F5E9), category: 'Activities'),
  AvatarOption(key: 'avatar_scooter', emoji: '🛵', bgColor: Color(0xFFE1F5FE), category: 'Activities'),
  AvatarOption(key: 'avatar_car', emoji: '🚗', bgColor: Color(0xFFFFCDD2), category: 'Activities'),
  AvatarOption(key: 'avatar_plane', emoji: '✈️', bgColor: Color(0xFFBBDEFB), category: 'Activities'),
  AvatarOption(key: 'avatar_boat', emoji: '⛵', bgColor: Color(0xFFB3E5FC), category: 'Activities'),
  AvatarOption(key: 'avatar_bulb', emoji: '💡', bgColor: Color(0xFFFFF9C4), category: 'Activities'),
];

/// Resolve an avatar key to its emoji display string.
String? getAvatarEmoji(String? avatarKey) {
  if (avatarKey == null || avatarKey.isEmpty) return null;
  try {
    return avatarOptions.firstWhere((a) => a.key == avatarKey).emoji;
  } catch (_) {
    return null;
  }
}

/// Build an avatar widget: if avatarKey is set, show emoji; otherwise fall back
/// to photo or letter avatar via [fallback].
Widget buildAvatarOrPhoto({
  String? avatarKey,
  required double radius,
  required Widget fallback,
  Color? bgColor,
}) {
  final emoji = getAvatarEmoji(avatarKey);
  if (emoji == null) return fallback;

  final bg = bgColor ??
      avatarOptions
          .firstWhere(
            (a) => a.key == avatarKey,
            orElse: () => const AvatarOption(
                key: '', emoji: '', bgColor: Color(0xFFE0E0E0)),
          )
          .bgColor;

  return ClipOval(
    child: Container(
      width: radius * 2,
      height: radius * 2,
      color: bg,
      alignment: Alignment.center,
      child: Text(emoji, style: TextStyle(fontSize: radius * 0.9)),
    ),
  );
}

