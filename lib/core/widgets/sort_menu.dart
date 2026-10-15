import 'package:flutter/material.dart';

class SortChoice {
  const SortChoice({
    required this.by,
    required this.order,
    required this.label,
  });

  final String by;
  final String order;
  final String label;
}

class SortMenuButton extends StatelessWidget {
  const SortMenuButton({
    super.key,
    required this.choices,
    required this.sortBy,
    required this.sortOrder,
    required this.onSelected,
  });

  final List<SortChoice> choices;
  final String sortBy;
  final String sortOrder;
  final void Function(String sortBy, String sortOrder) onSelected;

  @override
  Widget build(BuildContext context) {
    final current = choices.cast<SortChoice?>().firstWhere(
          (choice) => choice!.by == sortBy && choice.order == sortOrder,
          orElse: () => null,
        );
    return PopupMenuButton<int>(
      tooltip: current?.label ?? 'Sort',
      icon: const Icon(Icons.sort),
      onSelected: (index) {
        final choice = choices[index];
        onSelected(choice.by, choice.order);
      },
      itemBuilder: (context) => [
        for (var i = 0; i < choices.length; i++)
          PopupMenuItem(
            value: i,
            child: Text(
              choices[i].label,
              style: TextStyle(
                fontWeight: choices[i].by == sortBy && choices[i].order == sortOrder
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
          ),
      ],
    );
  }
}

List<SortChoice> nameSortChoices(String field, String label) => [
      SortChoice(by: field, order: 'asc', label: '$label A–Z'),
      SortChoice(by: field, order: 'desc', label: '$label Z–A'),
      const SortChoice(by: 'createdAt', order: 'desc', label: 'Newest'),
      const SortChoice(by: 'createdAt', order: 'asc', label: 'Oldest'),
    ];
