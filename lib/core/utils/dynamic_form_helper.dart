/// Helper terpusat untuk visibilitas dan pengurutan form dinamis bercabang
/// agar perilaku aplikasi mobile konsisten dengan Web (`DynamicField.tsx`).
class DynamicFormHelper {
  static String normalizeOption(dynamic value) {
    return (value ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[:\s]+$'), '');
  }

  static String? readParentFieldId(Map<String, dynamic> field) {
    final raw = field['parent_field_id'] ?? field['parentFieldId'];
    final str = raw?.toString().trim();
    if (str == null || str.isEmpty) return null;
    return str;
  }

  static dynamic readTriggerValue(Map<String, dynamic> field) {
    return field.containsKey('trigger_value')
        ? field['trigger_value']
        : field['triggerValue'];
  }

  static bool isFieldVisible(
    Map<String, dynamic> field,
    Map<String, dynamic> formData,
    List<Map<String, dynamic>> allFields, [
    Set<String>? visited,
  ]) {
    final parentId = readParentFieldId(field);
    if (parentId == null) {
      return true;
    }

    final seen = visited ?? <String>{};
    final currentId = field['id']?.toString() ?? '';
    if (currentId.isNotEmpty && !seen.add(currentId)) {
      return false;
    }

    Map<String, dynamic>? parentField;
    for (final candidate in allFields) {
      if (candidate['id']?.toString() == parentId) {
        parentField = candidate;
        break;
      }
    }

    if (parentField != null && !isFieldVisible(parentField, formData, allFields, seen)) {
      return false;
    }

    final parentValue = formData[parentId];
    if (parentValue == null) {
      return false;
    }

    final triggerValue = readTriggerValue(field);
    if (triggerValue is bool) {
      return parentValue == triggerValue;
    }

    final triggerStr = triggerValue?.toString() ?? '';
    if (triggerStr.isEmpty) {
      if (parentValue is List) {
        return parentValue.isNotEmpty;
      }
      return parentValue != '' && parentValue != false;
    }

    final normalizedTrigger = normalizeOption(triggerStr);
    if (parentValue is List) {
      return parentValue.any((item) => normalizeOption(item) == normalizedTrigger);
    }

    if (parentValue is bool) {
      if (parentValue) {
        return ['true', '1', 'ya', 'yes'].contains(normalizedTrigger);
      }
      return ['false', '0', 'tidak', 'no'].contains(normalizedTrigger);
    }

    return normalizeOption(parentValue) == normalizedTrigger;
  }

  /// Urutkan field sehingga field cabang berada tepat di bawah parent-nya.
  static List<Map<String, dynamic>> orderFieldsTree(List<Map<String, dynamic>> fields) {
    final roots = <Map<String, dynamic>>[];
    final childMap = <String, List<Map<String, dynamic>>>{};

    for (final f in fields) {
      final pid = readParentFieldId(f);
      if (pid == null) {
        roots.add(f);
      } else {
        childMap.putIfAbsent(pid, () => <Map<String, dynamic>>[]).add(f);
      }
    }

    final ordered = <Map<String, dynamic>>[];
    final addedIds = <String>{};

    void appendFieldAndChildren(Map<String, dynamic> field) {
      final id = field['id'].toString();
      if (!addedIds.add(id)) return;
      ordered.add(field);
      for (final child in (childMap[id] ?? const <Map<String, dynamic>>[])) {
        appendFieldAndChildren(child);
      }
    }

    for (final root in roots) {
      appendFieldAndChildren(root);
    }

    for (final f in fields) {
      if (addedIds.add(f['id'].toString())) {
        ordered.add(f);
      }
    }

    return ordered;
  }
}
