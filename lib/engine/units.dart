/// Unit registry and conversion.
///
/// Values are `double`; display rounds to 12 significant digits, which is
/// beyond the precision any notepad calculator user types.
/// shortcut: binary floating point, switch to a decimal type only if exact
/// money arithmetic (banking rounding) becomes a requirement.
library;

class Unit {
  final String id;
  final Map<String, int> dims; // e.g. {length: 1}, {data: 1, time: -1}
  final double factor; // multiplier to the base unit of each dimension
  final double offset; // for temperatures: base = (value + offset) * factor

  const Unit(this.id, this.dims, this.factor, {this.offset = 0});

  bool get isTemperature => dims.length == 1 && dims.containsKey('temp');

  Unit operator /(Unit other) => Unit(
    '$id/${other.id}',
    _combine(dims, other.dims, -1),
    factor / other.factor,
  );

  Unit operator *(Unit other) => Unit(
    '$id·${other.id}',
    _combine(dims, other.dims, 1),
    factor * other.factor,
  );

  static Map<String, int> _combine(
    Map<String, int> a,
    Map<String, int> b,
    int sign,
  ) {
    final out = <String, int>{...a};
    b.forEach((k, v) {
      final n = (out[k] ?? 0) + sign * v;
      if (n == 0) {
        out.remove(k);
      } else {
        out[k] = n;
      }
    });
    return out;
  }

  bool sameDimension(Unit other) {
    if (dims.length != other.dims.length) return false;
    for (final e in dims.entries) {
      if (other.dims[e.key] != e.value) return false;
    }
    return true;
  }
}

class UnitDef {
  final String id;
  final List<String> names; // lowercase aliases, first is canonical
  final String dim;
  final double factor;
  final double offset;

  const UnitDef(this.id, this.names, this.dim, this.factor, {this.offset = 0});
}

/// Base units: m, kg, s, byte, K, rad, m2, m3, J, Pa, W, Hz, L, mol.
const List<UnitDef> _defs = [
  // length (base: metre)
  UnitDef('mm', ['mm', 'millimetre', 'millimeter', '毫米'], 'length', 0.001),
  UnitDef('cm', ['cm', 'centimetre', 'centimeter', '公分', '厘米'], 'length', 0.01),
  UnitDef('m', ['m', 'metre', 'meter', '米'], 'length', 1),
  UnitDef('km', ['km', 'kilometre', 'kilometer', '公里', '千米'], 'length', 1000),
  UnitDef('in', ['in', 'inch', 'inches', '吋', '英寸'], 'length', 0.0254),
  UnitDef('ft', ['ft', 'foot', 'feet', '呎', '英尺'], 'length', 0.3048),
  UnitDef('yd', ['yd', 'yard', 'yards', '碼'], 'length', 0.9144),
  UnitDef('mi', ['mi', 'mile', 'miles', '英里'], 'length', 1609.344),
  UnitDef('nmi', ['nmi', 'nauticalmile'], 'length', 1852),
  UnitDef('pt', ['pt', 'point'], 'length', 0.000352777778),
  UnitDef('px', ['px', 'pixel', 'pixels'], 'length', 0.000264583333),
  UnitDef('em', ['em'], 'length', 0.00423333333),

  // mass (base: kg)
  UnitDef('mg', ['mg', 'milligram', '毫克'], 'mass', 0.000001),
  UnitDef('g', ['g', 'gram', 'grams', '克'], 'mass', 0.001),
  UnitDef('kg', ['kg', 'kilogram', 'kilograms', '公斤', '千克'], 'mass', 1),
  UnitDef('t', ['t', 'tonne', 'tonnes', '噸'], 'mass', 1000),
  UnitDef('oz', ['oz', 'ounce', 'ounces', '安士'], 'mass', 0.028349523125),
  UnitDef('lb', ['lb', 'lbs', 'pound', 'pounds', '磅'], 'mass', 0.45359237),
  UnitDef('st', ['st', 'stone'], 'mass', 6.35029318),

  // time (base: second)
  UnitDef('ms', ['ms', 'millisecond', 'milliseconds', '毫秒'], 'time', 0.001),
  UnitDef('s', ['s', 'sec', 'second', 'seconds', '秒'], 'time', 1),
  UnitDef('min', ['min', 'mins', 'minute', 'minutes', '分鐘', '分'], 'time', 60),
  UnitDef('h', ['h', 'hr', 'hrs', 'hour', 'hours', '小時', '钟头'], 'time', 3600),
  UnitDef('day', ['day', 'days', '日', '天'], 'time', 86400),
  UnitDef('week', ['week', 'weeks', '週', '星期'], 'time', 604800),
  UnitDef('month', ['month', 'months', '月'], 'time', 2629746),
  UnitDef('year', ['year', 'years', '年'], 'time', 31556952),

  // data (base: byte, decimal like Soulver)
  UnitDef('bit', ['bit', 'bits'], 'data', 0.125),
  UnitDef('B', ['b', 'byte', 'bytes'], 'data', 1),
  UnitDef('KB', ['kb', 'kilobyte', 'kilobytes'], 'data', 1000),
  UnitDef('MB', ['mb', 'megabyte', 'megabytes'], 'data', 1e6),
  UnitDef('GB', ['gb', 'gigabyte', 'gigabytes'], 'data', 1e9),
  UnitDef('TB', ['tb', 'terabyte', 'terabytes'], 'data', 1e12),
  UnitDef('KiB', ['kib', 'kibibyte'], 'data', 1024),
  UnitDef('MiB', ['mib', 'mebibyte'], 'data', 1048576),
  UnitDef('GiB', ['gib', 'gibibyte'], 'data', 1073741824),

  // area / volume (base: m2, m3)
  UnitDef('m2', ['m2', 'sqm', 'squaremetre', 'squaremeter'], 'area', 1),
  UnitDef('cm2', ['cm2'], 'area', 0.0001),
  UnitDef('km2', ['km2'], 'area', 1e6),
  UnitDef('ft2', ['ft2', 'sqft'], 'area', 0.09290304),
  UnitDef('ha', ['ha', 'hectare'], 'area', 10000),
  UnitDef('acre', ['acre', 'acres'], 'area', 4046.8564224),
  UnitDef('m3', ['m3', 'cbm', 'cubicmetre', 'cubicmeter'], 'volume', 1),
  UnitDef('L', ['l', 'litre', 'liter', 'litres', '公升', '升'], 'volume', 0.001),
  UnitDef('ml', ['ml', 'millilitre', 'milliliter'], 'volume', 0.000001),
  UnitDef('gal', ['gal', 'gallon', 'gallons'], 'volume', 0.003785411784),
  UnitDef('cup', ['cup', 'cups', '杯'], 'volume', 0.0002365882365),
  UnitDef('tbsp', ['tbsp'], 'volume', 0.0000147867648),
  UnitDef('tsp', ['tsp'], 'volume', 0.00000492892159),

  // speed (base: m/s)
  UnitDef('m/s', ['mps'], 'speed', 1),
  UnitDef('km/h', ['kph', 'kmh'], 'speed', 0.277777778),
  UnitDef('mph', ['mph'], 'speed', 0.44704),
  UnitDef('knot', ['knot', 'knots', 'kn'], 'speed', 0.514444444),

  // angle (base: radian)
  UnitDef('rad', ['rad', 'radian', 'radians'], 'angle', 1),
  UnitDef(
    'deg',
    ['deg', 'degree', 'degrees', '°'],
    'angle',
    0.017453292519943295,
  ),

  // temperature (base: kelvin)
  UnitDef('C', ['c', 'celsius', '°c', '攝氏'], 'temp', 1, offset: 273.15),
  UnitDef('F', ['f', 'fahrenheit', '°f', '華氏'], 'temp', 5 / 9, offset: 459.67),
  UnitDef('K', ['k', 'kelvin'], 'temp', 1),

  // energy / power / pressure / frequency
  UnitDef('J', ['j', 'joule', 'joules'], 'energy', 1),
  UnitDef('kJ', ['kj', 'kilojoule'], 'energy', 1000),
  UnitDef('cal', ['cal', 'calorie', 'calories', '卡路里'], 'energy', 4.184),
  UnitDef('kcal', ['kcal'], 'energy', 4184),
  UnitDef('kWh', ['kwh'], 'energy', 3600000),
  UnitDef('W', ['w', 'watt', 'watts', '瓦'], 'power', 1),
  UnitDef('kW', ['kw'], 'power', 1000),
  UnitDef('hp', ['hp', 'horsepower'], 'power', 745.699872),
  UnitDef('Pa', ['pa', 'pascal'], 'pressure', 1),
  UnitDef('kPa', ['kpa'], 'pressure', 1000),
  UnitDef('bar', ['bar'], 'pressure', 100000),
  UnitDef('psi', ['psi'], 'pressure', 6894.757293),
  UnitDef('Hz', ['hz', 'hertz'], 'frequency', 1),
  UnitDef('kHz', ['khz'], 'frequency', 1000),
  UnitDef('MHz', ['mhz'], 'frequency', 1e6),
  UnitDef('GHz', ['ghz'], 'frequency', 1e9),
];

class UnitRegistry {
  final Map<String, Unit> _byName = {};

  UnitRegistry() {
    for (final d in _defs) {
      final unit = Unit(d.id, {d.dim: 1}, d.factor, offset: d.offset);
      for (final n in d.names) {
        _byName[n.toLowerCase()] = unit;
      }
      _byName[d.id.toLowerCase()] = unit;
    }
    // compound data-rate units: dims are data/time, so they only convert
    // against each other
    const dataRate = {'data': 1, 'time': -1};
    _byName['mbps'] = const Unit('Mbps', dataRate, 125000);
    _byName['gbps'] = const Unit('Gbps', dataRate, 125000000);
    _byName['kbps'] = const Unit('kbps', dataRate, 125);
    _byName['mb/s'] = const Unit('MB/s', dataRate, 1000000);
    _byName['gb/s'] = const Unit('GB/s', dataRate, 1000000000);
    _byName['kb/s'] = const Unit('KB/s', dataRate, 1000);
  }

  Unit? lookup(String name) => _byName[name.toLowerCase()];

  bool isUnit(String name) => _byName.containsKey(name.toLowerCase());

  /// Convert [value] from [from] to [to]. Returns null on dimension mismatch.
  double? convert(double value, Unit from, Unit to) {
    if (!from.sameDimension(to)) return null;
    final base = (value + from.offset) * from.factor;
    return base / to.factor - to.offset;
  }

  /// Canonical unit for a dimension, used to normalise mixed additions.
  Unit baseFor(Unit u) {
    const bases = {
      'length': 'm',
      'mass': 'kg',
      'time': 's',
      'data': 'B',
      'area': 'm2',
      'volume': 'm3',
      'speed': 'm/s',
      'angle': 'rad',
      'temp': 'K',
      'energy': 'J',
      'power': 'W',
      'pressure': 'Pa',
      'frequency': 'Hz',
    };
    final dim = u.dims.keys.first;
    return _byName[bases[dim]] ?? u;
  }
}
