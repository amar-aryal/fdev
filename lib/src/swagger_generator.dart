import 'dart:convert';

class GeneratedApiModelFile {
  const GeneratedApiModelFile({required this.source, required this.classCount});

  final String source;
  final int classCount;
}

class SwaggerModelGenerator {
  SwaggerModelGenerator({required this.rootClassName, this.classPrefix = ''});

  final String rootClassName;
  final String classPrefix;

  final Map<String, String> _schemaClassNames = {};
  final Map<String, _ModelClass> _classes = {};
  final Set<String> _inProgress = {};

  GeneratedApiModelFile generate(
    String sourceText, {
    required String sourceName,
  }) {
    final decoded = jsonDecode(sourceText);
    if (decoded is! Map) {
      throw const FormatException('Expected a JSON object at the root.');
    }

    final root = _stringKeyedMap(decoded);
    _rootSpecCache = root;
    _schemaClassNames.clear();
    _classes.clear();
    _inProgress.clear();

    if (_looksLikeOpenApi(root)) {
      _generateFromOpenApi(root);
    } else {
      _ensureClass(
        _safeClassName(rootClassName),
        root,
        originalName: rootClassName,
      );
    }

    return GeneratedApiModelFile(
      source: _renderFile(sourceName),
      classCount: _classes.length,
    );
  }

  bool _looksLikeOpenApi(Map<String, dynamic> root) {
    return root.containsKey('openapi') ||
        root.containsKey('swagger') ||
        root.containsKey('paths') ||
        root.containsKey('components') ||
        root.containsKey('definitions');
  }

  void _generateFromOpenApi(Map<String, dynamic> spec) {
    final schemas = _schemaDefinitions(spec);
    for (final entry in schemas.entries) {
      _schemaClassNames.putIfAbsent(
        entry.key,
        () => _uniqueClassName('$classPrefix${_safeClassName(entry.key)}'),
      );
    }

    for (final entry in schemas.entries) {
      _ensureClass(
        _classNameForSchema(entry.key),
        _stringKeyedMap(entry.value),
        originalName: entry.key,
      );
    }

    _collectInlineResponseSchemas(spec);

    if (_classes.isEmpty) {
      _ensureClass(
        _safeClassName(rootClassName),
        spec,
        originalName: rootClassName,
      );
    }
  }

  Map<String, dynamic> _schemaDefinitions(Map<String, dynamic> spec) {
    final components = _maybeMap(spec['components']);
    final schemas = _maybeMap(components?['schemas']);
    final definitions = _maybeMap(spec['definitions']);

    return <String, dynamic>{
      if (schemas != null) ...schemas,
      if (definitions != null) ...definitions,
    };
  }

  void _collectInlineResponseSchemas(Map<String, dynamic> spec) {
    final paths = _maybeMap(spec['paths']);
    if (paths == null) {
      return;
    }

    for (final pathEntry in paths.entries) {
      final path = pathEntry.key;
      final operations = _maybeMap(pathEntry.value);
      if (operations == null) {
        continue;
      }

      for (final operationEntry in operations.entries) {
        final method = operationEntry.key.toLowerCase();
        if (!_httpMethods.contains(method)) {
          continue;
        }

        final operation = _maybeMap(operationEntry.value);
        if (operation == null) {
          continue;
        }

        final operationName = _operationName(operation, method, path);
        final responses = _maybeMap(operation['responses']);
        if (responses == null) {
          continue;
        }

        for (final responseEntry in responses.entries) {
          final schema = _responseSchema(responseEntry.value);
          if (schema == null || schema.containsKey(r'$ref')) {
            continue;
          }
          if (!_isObjectLikeSchema(schema)) {
            continue;
          }

          final status = _safeClassName(responseEntry.key);
          final className = _uniqueClassName(
            '$classPrefix$operationName${status}Response',
          );
          _ensureClass(
            className,
            schema,
            originalName: '$operationName ${responseEntry.key}',
          );
        }
      }
    }
  }

  Map<String, dynamic>? _responseSchema(Object? responseValue) {
    final response = _maybeMap(responseValue);
    if (response == null) {
      return null;
    }

    final directSchema = _maybeMap(response['schema']);
    if (directSchema != null) {
      return directSchema;
    }

    final content = _maybeMap(response['content']);
    if (content == null) {
      return null;
    }

    final preferred = content['application/json'] ??
        content['application/*+json'] ??
        content.values.cast<Object?>().firstWhere(
              (value) => _maybeMap(value)?['schema'] != null,
              orElse: () => null,
            );
    return _maybeMap(_maybeMap(preferred)?['schema']);
  }

  void _ensureClass(
    String className,
    Map<String, dynamic> schema, {
    required String originalName,
  }) {
    if (_classes.containsKey(className) || _inProgress.contains(className)) {
      return;
    }

    _inProgress.add(className);
    final normalized = _normalizeComposedSchema(schema);
    final fields = _fieldsForSchema(className, normalized);
    _classes[className] = _ModelClass(
      name: className,
      originalName: originalName,
      fields: fields,
    );
    _inProgress.remove(className);
  }

  List<_ModelField> _fieldsForSchema(
    String className,
    Map<String, dynamic> schema,
  ) {
    final properties = _maybeMap(schema['properties']);
    if (properties != null && properties.isNotEmpty) {
      final usedFieldNames = <String>{};
      final requiredKeys = _requiredPropertyKeys(schema);
      return [
        for (final entry in properties.entries)
          _fieldForProperty(
            className: className,
            jsonKey: entry.key,
            value: entry.value,
            isRequired: requiredKeys.contains(entry.key),
            usedFieldNames: usedFieldNames,
          ),
      ];
    }

    final schemaType = _schemaType(schema);
    if (schemaType == 'array') {
      return [
        _ModelField(
          jsonKey: 'items',
          name: 'items',
          type: _describeSchema(
            _maybeMap(schema['items']) ?? const <String, dynamic>{},
            '${className}Item',
          ),
          isRequired: false,
          isNullable: _isNullableSchema(schema),
        ),
      ];
    }

    if (schema.containsKey('additionalProperties')) {
      return [
        _ModelField(
          jsonKey: 'values',
          name: 'values',
          type: _TypeDescriptor.map(
            _describeSchema(
              _maybeMap(schema['additionalProperties']) ??
                  const <String, dynamic>{},
              '${className}Value',
            ),
          ),
          isRequired: false,
          isNullable: _isNullableSchema(schema),
        ),
      ];
    }

    if (!_isObjectLikeSchema(schema)) {
      return [
        _ModelField(
          jsonKey: 'value',
          name: 'value',
          type: _describeSchema(schema, '${className}Value'),
          isRequired: false,
          isNullable: _isNullableSchema(schema),
        ),
      ];
    }

    return const <_ModelField>[];
  }

  _ModelField _fieldForProperty({
    required String className,
    required String jsonKey,
    required Object? value,
    required bool isRequired,
    required Set<String> usedFieldNames,
  }) {
    final fieldName = _uniqueFieldName(_safeFieldName(jsonKey), usedFieldNames);
    final propertySchema = _maybeMap(value) ?? const <String, dynamic>{};
    final propertyClassName = '$className${_safeClassName(jsonKey)}';
    return _ModelField(
      jsonKey: jsonKey,
      name: fieldName,
      type: _describeSchema(
        _schemaWithoutNullVariant(propertySchema),
        propertyClassName,
      ),
      isRequired: isRequired,
      isNullable: _isNullableSchema(propertySchema),
    );
  }

  _TypeDescriptor _describeSchema(
    Map<String, dynamic> schema,
    String contextClassName,
  ) {
    final ref = schema[r'$ref'];
    if (ref is String) {
      final schemaName = _schemaNameFromRef(ref);
      final className = _classNameForSchema(schemaName);
      final schemaMap = _schemaDefinitions(_rootSpecCache)[schemaName];
      if (schemaMap is Map) {
        _ensureClass(
          className,
          _stringKeyedMap(schemaMap),
          originalName: schemaName,
        );
      }
      return _TypeDescriptor.model(className);
    }

    final normalized = _normalizeComposedSchema(schema);
    final type = _schemaType(normalized);
    final format = normalized['format'];

    if (type == 'array') {
      final items = _maybeMap(normalized['items']) ?? const <String, dynamic>{};
      return _TypeDescriptor.list(
        _describeSchema(items, '${contextClassName}Item'),
      );
    }

    if (type == 'object' || _isObjectLikeSchema(normalized)) {
      final properties = _maybeMap(normalized['properties']);
      final additionalProperties = normalized['additionalProperties'];
      if ((properties == null || properties.isEmpty) &&
          additionalProperties != null) {
        final valueSchema =
            _maybeMap(additionalProperties) ?? const <String, dynamic>{};
        return _TypeDescriptor.map(
          _describeSchema(valueSchema, '${contextClassName}Value'),
        );
      }

      if (properties != null && properties.isNotEmpty) {
        final className = _uniqueClassName(
          '$classPrefix${_safeClassName(contextClassName)}',
        );
        _ensureClass(className, normalized, originalName: contextClassName);
        return _TypeDescriptor.model(className);
      }

      return _TypeDescriptor.dynamicMap();
    }

    if (type == 'integer') {
      return const _TypeDescriptor.scalar(_TypeKind.integer, 'int');
    }
    if (type == 'number') {
      return const _TypeDescriptor.scalar(_TypeKind.doubleNumber, 'double');
    }
    if (type == 'boolean') {
      return const _TypeDescriptor.scalar(_TypeKind.boolean, 'bool');
    }
    if (type == 'string' && (format == 'date-time' || format == 'date')) {
      return const _TypeDescriptor.scalar(_TypeKind.dateTime, 'DateTime');
    }
    if (type == 'string' || normalized.containsKey('enum')) {
      return const _TypeDescriptor.scalar(_TypeKind.string, 'String');
    }

    return const _TypeDescriptor.dynamicValue();
  }

  late Map<String, dynamic> _rootSpecCache;

  String _renderFile(String sourceName) {
    final buffer = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln('// Generated by fdev swagger from: $sourceName')
      ..writeln()
      ..writeln('// ignore_for_file: avoid_dynamic_calls, unused_element')
      ..writeln();

    for (final model in _classes.values) {
      buffer..writeln('class ${model.name} {');
      if (model.fields.isEmpty) {
        buffer.writeln('  const ${model.name}();');
      } else {
        buffer.writeln('  const ${model.name}({');
        for (final field in model.fields) {
          final requiredKeyword = field.isRequired ? 'required ' : '';
          buffer.writeln('    ${requiredKeyword}this.${field.name},');
        }
        buffer.writeln('  });');
      }
      buffer.writeln();

      for (final field in model.fields) {
        buffer.writeln('  final ${field.dartType} ${field.name};');
      }

      if (model.fields.isNotEmpty) {
        buffer.writeln();
      }

      buffer
        ..writeln(
          '  factory ${model.name}.fromJson(Map<String, dynamic> json) {',
        );
      if (model.fields.isEmpty) {
        buffer.writeln('    return ${model.name}();');
      } else {
        buffer.writeln('    return ${model.name}(');
        for (final field in model.fields) {
          final jsonKey = _escapeSingleQuote(field.jsonKey);
          final jsonValue = field.isRequired
              ? "_requiredKey(json, '$jsonKey')"
              : "json['$jsonKey']";
          final value = _readValue(field.type, jsonValue);
          final readExpression = field.requiresNonNullJsonValue
              ? "_required($value, '$jsonKey')"
              : field.isRequired
                  ? _readNullableRequired(field.type, jsonValue, jsonKey)
                  : value;
          buffer.writeln(
            '      ${field.name}: $readExpression,',
          );
        }
        buffer.writeln('    );');
      }
      buffer
        ..writeln('  }')
        ..writeln()
        ..writeln('  Map<String, dynamic> toJson() {')
        ..writeln('    return <String, dynamic>{');
      for (final field in model.fields) {
        final value = field.requiresNonNullJsonValue
            ? _writeNonNull(field.type, field.name)
            : _writeNullable(field.type, field.name);
        buffer.writeln(
          "      '${_escapeSingleQuote(field.jsonKey)}': $value,",
        );
      }
      buffer
        ..writeln('    };')
        ..writeln('  }')
        ..writeln('}')
        ..writeln();
    }

    buffer.write(_helperSource);
    return buffer.toString();
  }

  Map<String, dynamic> _normalizeComposedSchema(Map<String, dynamic> schema) {
    final allOf = schema['allOf'];
    if (allOf is! List) {
      return schema;
    }

    final merged = <String, dynamic>{...schema}..remove('allOf');
    final properties = <String, dynamic>{};
    final required = <String>{};

    for (final item in allOf) {
      final itemMap = _maybeMap(item);
      if (itemMap == null) {
        continue;
      }
      final ref = itemMap[r'$ref'];
      final resolved = ref is String ? _resolveRef(ref) : itemMap;
      final normalized = _normalizeComposedSchema(resolved);
      properties.addAll(
        _maybeMap(normalized['properties']) ?? const <String, dynamic>{},
      );
      final requiredValues = normalized['required'];
      if (requiredValues is List) {
        required.addAll(requiredValues.map((value) => value.toString()));
      }
      for (final entry in normalized.entries) {
        if (entry.key != 'properties' && entry.key != 'required') {
          merged.putIfAbsent(entry.key, () => entry.value);
        }
      }
    }

    properties.addAll(
      _maybeMap(schema['properties']) ?? const <String, dynamic>{},
    );
    final schemaRequired = schema['required'];
    if (schemaRequired is List) {
      required.addAll(schemaRequired.map((value) => value.toString()));
    }

    if (properties.isNotEmpty) {
      merged['type'] = 'object';
      merged['properties'] = properties;
    }
    if (required.isNotEmpty) {
      merged['required'] = required.toList();
    }
    return merged;
  }

  Set<String> _requiredPropertyKeys(Map<String, dynamic> schema) {
    final required = schema['required'];
    if (required is! List) {
      return const <String>{};
    }
    return required.map((value) => value.toString()).toSet();
  }

  bool _isNullableSchema(Map<String, dynamic> schema) {
    if (schema['nullable'] == true || schema['x-nullable'] == true) {
      return true;
    }

    final type = schema['type'];
    if (type is List && type.contains('null')) {
      return true;
    }

    return _hasNullSchemaVariant(schema['oneOf']) ||
        _hasNullSchemaVariant(schema['anyOf']);
  }

  bool _hasNullSchemaVariant(Object? value) {
    if (value is! List) {
      return false;
    }
    return value.any((item) => _maybeMap(item)?['type'] == 'null');
  }

  Map<String, dynamic> _schemaWithoutNullVariant(Map<String, dynamic> schema) {
    final type = schema['type'];
    if (type is List && type.contains('null')) {
      final nonNullTypes = type.where((value) => value != 'null').toList();
      return <String, dynamic>{
        ...schema,
        if (nonNullTypes.length == 1) 'type': nonNullTypes.single,
        if (nonNullTypes.length > 1) 'type': nonNullTypes,
      };
    }

    for (final key in const ['oneOf', 'anyOf']) {
      final variants = schema[key];
      if (variants is! List) {
        continue;
      }
      final nonNullVariants = variants
          .map(_maybeMap)
          .where((variant) => variant != null && variant['type'] != 'null')
          .cast<Map<String, dynamic>>()
          .toList();
      if (nonNullVariants.length == 1) {
        return <String, dynamic>{
          ...schema,
          ...nonNullVariants.single,
        }..remove(key);
      }
    }

    return schema;
  }

  Map<String, dynamic> _resolveRef(String ref) {
    final schemaName = _schemaNameFromRef(ref);
    final schema = _schemaDefinitions(_rootSpecCache)[schemaName];
    if (schema is Map) {
      return _stringKeyedMap(schema);
    }
    return const <String, dynamic>{};
  }

  String _readValue(_TypeDescriptor type, String jsonExpression) {
    switch (type.kind) {
      case _TypeKind.dynamicValue:
        return jsonExpression;
      case _TypeKind.dynamicMap:
        return '_jsonMap($jsonExpression)';
      case _TypeKind.string:
        return '_string($jsonExpression)';
      case _TypeKind.integer:
        return '_int($jsonExpression)';
      case _TypeKind.doubleNumber:
        return '_double($jsonExpression)';
      case _TypeKind.boolean:
        return '_bool($jsonExpression)';
      case _TypeKind.dateTime:
        return '_dateTime($jsonExpression)';
      case _TypeKind.model:
        return '_object($jsonExpression, ${type.className}.fromJson)';
      case _TypeKind.list:
        return '_list($jsonExpression, (value) => ${_readValue(type.item!, 'value')})';
      case _TypeKind.map:
        return '_map($jsonExpression, (value) => ${_readValue(type.value!, 'value')})';
    }
  }

  String _readNullableRequired(
    _TypeDescriptor type,
    String jsonExpression,
    String jsonKey,
  ) {
    if (type.kind == _TypeKind.dynamicValue) {
      return jsonExpression;
    }

    return "_nullableRequired($jsonExpression, (value) => ${_readValue(type, 'value')}, '$jsonKey')";
  }

  String _writeNullable(_TypeDescriptor type, String expression) {
    switch (type.kind) {
      case _TypeKind.model:
        return '$expression?.toJson()';
      case _TypeKind.dateTime:
        return '$expression?.toIso8601String()';
      case _TypeKind.list:
        if (!_needsJsonTransform(type.item!)) {
          return expression;
        }
        return '$expression?.map((value) => ${_writeNonNull(type.item!, 'value')}).toList()';
      case _TypeKind.map:
        if (!_needsJsonTransform(type.value!)) {
          return expression;
        }
        return '$expression?.map((key, value) => MapEntry(key, ${_writeNonNull(type.value!, 'value')}))';
      case _TypeKind.dynamicValue:
      case _TypeKind.dynamicMap:
      case _TypeKind.string:
      case _TypeKind.integer:
      case _TypeKind.doubleNumber:
      case _TypeKind.boolean:
        return expression;
    }
  }

  String _writeNonNull(_TypeDescriptor type, String expression) {
    switch (type.kind) {
      case _TypeKind.model:
        return '$expression.toJson()';
      case _TypeKind.dateTime:
        return '$expression.toIso8601String()';
      case _TypeKind.list:
        if (!_needsJsonTransform(type.item!)) {
          return expression;
        }
        return '$expression.map((value) => ${_writeNonNull(type.item!, 'value')}).toList()';
      case _TypeKind.map:
        if (!_needsJsonTransform(type.value!)) {
          return expression;
        }
        return '$expression.map((key, value) => MapEntry(key, ${_writeNonNull(type.value!, 'value')}))';
      case _TypeKind.dynamicValue:
      case _TypeKind.dynamicMap:
      case _TypeKind.string:
      case _TypeKind.integer:
      case _TypeKind.doubleNumber:
      case _TypeKind.boolean:
        return expression;
    }
  }

  bool _needsJsonTransform(_TypeDescriptor type) {
    return type.kind == _TypeKind.model ||
        type.kind == _TypeKind.dateTime ||
        type.kind == _TypeKind.list ||
        type.kind == _TypeKind.map;
  }

  String _classNameForSchema(String schemaName) {
    return _schemaClassNames.putIfAbsent(
      schemaName,
      () => _uniqueClassName('$classPrefix${_safeClassName(schemaName)}'),
    );
  }

  String _uniqueClassName(String preferred) {
    final base = _safeClassName(preferred);
    if (!_classes.containsKey(base) &&
        !_schemaClassNames.containsValue(base) &&
        !_inProgress.contains(base)) {
      return base;
    }

    var index = 2;
    while (true) {
      final candidate = '$base$index';
      if (!_classes.containsKey(candidate) &&
          !_schemaClassNames.containsValue(candidate) &&
          !_inProgress.contains(candidate)) {
        return candidate;
      }
      index++;
    }
  }

  String _operationName(
    Map<String, dynamic> operation,
    String method,
    String path,
  ) {
    final operationId = operation['operationId'];
    if (operationId is String && operationId.trim().isNotEmpty) {
      return _safeClassName(operationId);
    }

    final pathName = path
        .split('/')
        .where((part) => part.trim().isNotEmpty)
        .map((part) => part.replaceAll('{', '').replaceAll('}', ''))
        .map(_safeClassName)
        .join();
    return _safeClassName('$method$pathName');
  }

  String? _schemaType(Map<String, dynamic> schema) {
    final type = schema['type'];
    if (type is String) {
      return type;
    }
    if (type is List) {
      return type
          .firstWhere((value) => value != 'null', orElse: () => 'dynamic')
          .toString();
    }
    if (schema.containsKey('properties')) {
      return 'object';
    }
    if (schema.containsKey('items')) {
      return 'array';
    }
    return null;
  }

  bool _isObjectLikeSchema(Map<String, dynamic> schema) {
    return schema.containsKey('properties') ||
        schema.containsKey('additionalProperties') ||
        _schemaType(schema) == 'object';
  }
}

class _ModelClass {
  const _ModelClass({
    required this.name,
    required this.originalName,
    required this.fields,
  });

  final String name;
  final String originalName;
  final List<_ModelField> fields;
}

class _ModelField {
  const _ModelField({
    required this.jsonKey,
    required this.name,
    required this.type,
    required this.isRequired,
    required this.isNullable,
  });

  final String jsonKey;
  final String name;
  final _TypeDescriptor type;
  final bool isRequired;
  final bool isNullable;

  bool get requiresNonNullJsonValue => isRequired && !isNullable;

  String get dartType =>
      requiresNonNullJsonValue ? type.dartType : type.nullableDartType;
}

enum _TypeKind {
  dynamicValue,
  dynamicMap,
  string,
  integer,
  doubleNumber,
  boolean,
  dateTime,
  model,
  list,
  map,
}

class _TypeDescriptor {
  const _TypeDescriptor.scalar(this.kind, this.dartType)
      : className = null,
        item = null,
        value = null;

  const _TypeDescriptor.dynamicValue()
      : kind = _TypeKind.dynamicValue,
        dartType = 'dynamic',
        className = null,
        item = null,
        value = null;

  const _TypeDescriptor.dynamicMap()
      : kind = _TypeKind.dynamicMap,
        dartType = 'Map<String, dynamic>',
        className = null,
        item = null,
        value = null;

  const _TypeDescriptor.model(String this.className)
      : kind = _TypeKind.model,
        dartType = className,
        item = null,
        value = null;

  _TypeDescriptor.list(_TypeDescriptor this.item)
      : kind = _TypeKind.list,
        dartType = 'List<${item.dartType}>',
        className = null,
        value = null;

  _TypeDescriptor.map(_TypeDescriptor this.value)
      : kind = _TypeKind.map,
        dartType = 'Map<String, ${value.dartType}>',
        className = null,
        item = null;

  final _TypeKind kind;
  final String dartType;
  final String? className;
  final _TypeDescriptor? item;
  final _TypeDescriptor? value;

  String get nullableDartType =>
      dartType == 'dynamic' ? 'dynamic' : '$dartType?';
}

const Set<String> _httpMethods = {
  'get',
  'put',
  'post',
  'delete',
  'options',
  'head',
  'patch',
  'trace',
};

Map<String, dynamic> _stringKeyedMap(Map<dynamic, dynamic> map) {
  return map.map((key, value) => MapEntry(key.toString(), value));
}

Map<String, dynamic>? _maybeMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return _stringKeyedMap(value);
  }
  return null;
}

String _schemaNameFromRef(String ref) {
  final last = ref.split('/').last;
  return Uri.decodeComponent(last.replaceAll('~1', '/').replaceAll('~0', '~'));
}

String _safeClassName(String value) {
  final words = _words(value);
  final name = words.isEmpty ? 'GeneratedModel' : words.map(_capitalize).join();
  final startsWithDigit = RegExp(r'^[0-9]').hasMatch(name);
  return startsWithDigit ? 'Model$name' : name;
}

String _safeFieldName(String value) {
  final words = _words(value);
  final fallback = words.isEmpty
      ? 'value'
      : words.first.toLowerCase() + words.skip(1).map(_capitalize).join();
  final startsWithDigit = RegExp(r'^[0-9]').hasMatch(fallback);
  final name = startsWithDigit ? 'value$fallback' : fallback;
  return _reservedWords.contains(name) ? '${name}Value' : name;
}

String _uniqueFieldName(String preferred, Set<String> used) {
  if (used.add(preferred)) {
    return preferred;
  }
  var index = 2;
  while (!used.add('$preferred$index')) {
    index++;
  }
  return '$preferred$index';
}

List<String> _words(String value) {
  final spaced = value
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match[1]} ${match[2]}',
      )
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ');
  return spaced
      .split(' ')
      .map((word) => word.trim())
      .where((word) => word.isNotEmpty)
      .toList();
}

String _capitalize(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value.substring(0, 1).toUpperCase() + value.substring(1).toLowerCase();
}

String _escapeSingleQuote(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

const Set<String> _reservedWords = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'Function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};

const String _helperSource = r'''
Object? _requiredKey(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('Missing required key "$key".');
  }
  return json[key];
}

T _required<T>(T? value, String key) {
  if (value == null) {
    throw FormatException('Missing required non-null value "$key".');
  }
  return value;
}

T? _nullableRequired<T>(
  Object? value,
  T? Function(Object? value) convert,
  String key,
) {
  if (value == null) {
    return null;
  }
  final converted = convert(value);
  if (converted == null) {
    throw FormatException('Invalid required value "$key".');
  }
  return converted;
}

Map<String, dynamic>? _jsonMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

T? _object<T>(Object? value, T Function(Map<String, dynamic>) fromJson) {
  final map = _jsonMap(value);
  return map == null ? null : fromJson(map);
}

List<T>? _list<T>(Object? value, T? Function(Object? value) convert) {
  if (value is! List) {
    return null;
  }
  return value.map(convert).whereType<T>().toList();
}

Map<String, T>? _map<T>(Object? value, T? Function(Object? value) convert) {
  final map = _jsonMap(value);
  if (map == null) {
    return null;
  }
  final result = <String, T>{};
  for (final entry in map.entries) {
    final converted = convert(entry.value);
    if (converted != null) {
      result[entry.key] = converted;
    }
  }
  return result;
}

String? _string(Object? value) => value?.toString();

int? _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

double? _double(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

bool? _bool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
  }
  return null;
}

DateTime? _dateTime(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}
''';
