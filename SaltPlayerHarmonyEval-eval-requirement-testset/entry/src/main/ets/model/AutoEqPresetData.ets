// AutoEqData.ets - AutoEQ 预设数据
// 对应 Android: player/bass/AutoEq.kt, ParametricEQ.kt, BAND.kt

export enum BAND {
  NONE,
  AKG,
  APPLE,
  BEATS,
  BOSE,
  EDIFIER,
  GOOGLE,
  HZSOUND,
  MOONDROP,
  NICEHCK,
  ONEPLUS,
  OPPO,
  QCY,
  SAMSUNG,
  SENNHEISER,
  SIMGOT,
  SONY,
  TFZ,
  VSONIC,
  WHIZZER,
  XIAOMI
}

export class EqItem {
  Fc: number = 0
  Q: number = 0
  Gain: number = 0

  constructor(fc: number, q: number, gain: number) {
    this.Fc = fc
    this.Q = q
    this.Gain = gain
  }
}

export class ParametricEQ {
  band: BAND = BAND.NONE
  name: string = ''
  author: string = ''
  Preamp: number = 0
  items: EqItem[] = []
  tag: string = ''

  constructor(band: BAND, name: string, author: string, preamp: number, items: EqItem[], tag: string = '') {
    this.band = band
    this.name = name
    this.author = author
    this.Preamp = preamp
    this.items = items
    this.tag = tag
  }
}

// ===== 预设数据 =====

const NONE_Original: ParametricEQ = new ParametricEQ(
  BAND.NONE, 'Original Sound', 'Moriafly', 0, [], '定制原声'
)

const Mega_bass: ParametricEQ = new ParametricEQ(
  BAND.NONE, '低音 Bass', 'Moriafly', -3.4,
  [new EqItem(31, 1.41, 2.1), new EqItem(62, 1.41, 3), new EqItem(125, 1.41, 2),
    new EqItem(250, 1.41, 0), new EqItem(500, 1.41, -1.2), new EqItem(1000, 1.41, 0.6)],
  '通用'
)

const Clear: ParametricEQ = new ParametricEQ(
  BAND.NONE, '清澈 Clear V2', 'Syaoran', -3.2,
  [new EqItem(400, 1.41, 3), new EqItem(1000, 1.41, 7), new EqItem(2500, 1.41, 10),
    new EqItem(6300, 1.41, 10), new EqItem(16000, 1.41, 8)],
  '通用'
)

const Clear_V2: ParametricEQ = new ParametricEQ(
  BAND.NONE, '清澈悦耳', 'Moriafly', -1.5,
  [new EqItem(75, 0.2, 0.8), new EqItem(150, 4, -2.2), new EqItem(250, 4.8, -2.8),
    new EqItem(50, 4, -2), new EqItem(800, 5.8, 1.25), new EqItem(4060, 3.2, 1.67),
    new EqItem(8000, 4.3, -1.67), new EqItem(12000, 1.2, 0.1)],
  '椒盐自调'
)

const AKG_K240_MKII: ParametricEQ = new ParametricEQ(
  BAND.AKG, 'AKG K240 MKII', 'Headphone.com', -6.3,
  [new EqItem(26, 0.43, 6.6), new EqItem(131, 0.61, -4.7), new EqItem(1171, 0.71, 6.4),
    new EqItem(4572, 0.24, -7.9), new EqItem(4677, 0.88, 10.8), new EqItem(1747, 2.41, 1.6),
    new EqItem(2331, 1.58, -1.5), new EqItem(2440, 2.38, -0.7), new EqItem(3432, 3.38, 2.7),
    new EqItem(4142, 3.24, -1.1)]
)

const Apple_AirPods: ParametricEQ = new ParametricEQ(
  BAND.APPLE, 'Apple AirPods', 'oratory1990', -6.6,
  [new EqItem(33, 0.41, 6.4), new EqItem(1765, 0.19, 3.5), new EqItem(2034, 0.86, -7.1),
    new EqItem(9552, 0.29, -2.6), new EqItem(19050, 0.48, 2.6), new EqItem(60, 5.14, 0.9),
    new EqItem(2887, 4.93, -1.4), new EqItem(3998, 1.57, 1.3), new EqItem(5490, 3.51, -3.4),
    new EqItem(6577, 4.97, 2.9)]
)

const Apple_AirPods_Max: ParametricEQ = new ParametricEQ(
  BAND.APPLE, 'Apple AirPods Max', 'Crinacle, GRAS 43AG-7', -5.3,
  [new EqItem(2157, 3.5, 2.0), new EqItem(4216, 2.09, 4.3), new EqItem(7699, 1.09, 3.7),
    new EqItem(19491, 0.39, -9.6), new EqItem(23, 0.64, -6.7), new EqItem(36, 1.61, -2.6),
    new EqItem(126, 0.7, -2.3), new EqItem(258, 1.54, -1.6), new EqItem(917, 1.69, -2.5)]
)

const Apple_AirPods_Pro: ParametricEQ = new ParametricEQ(
  BAND.APPLE, 'Apple AirPods Pro', 'Rtings', -6.6,
  [new EqItem(21, 2.71, 1.1), new EqItem(539, 1.17, -4.4), new EqItem(1534, 1.32, -2.1),
    new EqItem(4329, 2.38, 2.7), new EqItem(8622, 0.54, 5.0), new EqItem(53, 1.15, -0.9),
    new EqItem(141, 1.78, 1.2), new EqItem(6312, 3.35, 2.2), new EqItem(9536, 0.92, 2.2),
    new EqItem(11139, 2.17, -3.1)],
  '热门'
)

const Beats_Pro: ParametricEQ = new ParametricEQ(
  BAND.BEATS, 'Beats Pro', 'Innerfidelity', -5.5,
  [new EqItem(20, 1.42, 5.2), new EqItem(137, 0.5, -3.5), new EqItem(1789, 0.59, 5.0),
    new EqItem(2673, 2.22, -9.4), new EqItem(6388, 2.5, 2.5), new EqItem(380, 5.43, 1.0),
    new EqItem(3999, 5.28, 3.1), new EqItem(4535, 3.74, -2.3), new EqItem(11051, 2.39, -0.9),
    new EqItem(19977, 0.37, 4.7)]
)

const Bose_QuietComfort_35_II: ParametricEQ = new ParametricEQ(
  BAND.BOSE, 'Bose QuietComfort 35 II', 'Rtings', -3.7,
  [new EqItem(15, 1.19, -4.1), new EqItem(60, 0.61, -3.4), new EqItem(178, 1.34, -2.4),
    new EqItem(6401, 4.37, -6.3), new EqItem(9543, 1.46, 3.8), new EqItem(741, 1.64, 1.2),
    new EqItem(1456, 1.9, 2.8), new EqItem(2144, 1.48, -2.2), new EqItem(3202, 4.74, 2.1),
    new EqItem(7503, 2.8, -0.2)]
)

const Google_Pixel_Buds_2: ParametricEQ = new ParametricEQ(
  BAND.GOOGLE, 'Google Pixel Buds 2', 'Rtings', -6.8,
  [new EqItem(20, 0.79, 3.0), new EqItem(748, 0.51, -2.7), new EqItem(1954, 1.21, 1.5),
    new EqItem(5976, 2.57, 5.4), new EqItem(18084, 0.38, 6.5), new EqItem(210, 2.96, 0.8),
    new EqItem(325, 4.11, -0.8), new EqItem(2651, 3.4, -0.8), new EqItem(3416, 4.15, 1.4),
    new EqItem(9556, 3.2, -0.5)]
)

const HZSOUND_Heart_Mirror: ParametricEQ = new ParametricEQ(
  BAND.HZSOUND, 'HZSOUND Heart Mirror', 'Satria Tarigan', -6.7,
  [new EqItem(21, 1.64, 2.3), new EqItem(939, 1.32, 1.9), new EqItem(3332, 1.96, 2.8),
    new EqItem(9817, 1.16, -7.9), new EqItem(17737, 0.33, 6.9), new EqItem(165, 1.05, -1.8),
    new EqItem(524, 2.62, 0.9), new EqItem(6303, 4.95, 2.8), new EqItem(6908, 2.46, -1.6),
    new EqItem(20080, 2.89, 0.6)]
)

const Moondrop_Quarks: ParametricEQ = new ParametricEQ(
  BAND.MOONDROP, 'Moondrop Quarks', 'Crinacle', -5.9,
  [new EqItem(164, 0.51, -4.0), new EqItem(818, 1.12, 2.8), new EqItem(2917, 3.85, -5.5),
    new EqItem(4342, 1.35, 3.8), new EqItem(10004, 1.39, 5.3), new EqItem(21, 1.42, 0.6),
    new EqItem(963, 3.39, 0.1), new EqItem(8063, 4.99, 0.4), new EqItem(13649, 1.95, 1.6),
    new EqItem(19875, 0.6, -5.9)],
  '水月雨 夸克'
)

const Moondrop_Spaceship: ParametricEQ = new ParametricEQ(
  BAND.MOONDROP, 'Moondrop Spaceship', 'Crinacle', -6.3,
  [new EqItem(23, 0.63, 6.3), new EqItem(178, 0.43, -3.0), new EqItem(791, 0.79, 2.8),
    new EqItem(3019, 5.11, -3.0), new EqItem(8560, 1.76, 3.4), new EqItem(4782, 2.96, 1.6),
    new EqItem(10598, 2.73, 1.8), new EqItem(12763, 1.49, 2.0), new EqItem(19759, 0.38, -11.2)],
  '水月雨 银色飞船'
)

const Moondrop_SSP: ParametricEQ = new ParametricEQ(
  BAND.MOONDROP, 'Moondrop SSP', 'Crinacle', -4.6,
  [new EqItem(17, 0.54, 3.5), new EqItem(166, 0.56, -3.1), new EqItem(823, 1.32, 3.5),
    new EqItem(5916, 3.09, 2.4), new EqItem(9200, 2.36, 4.1), new EqItem(2167, 2.86, 1.0),
    new EqItem(3091, 2.25, -2.9), new EqItem(4667, 2.67, 1.2), new EqItem(12046, 1.44, 2.5),
    new EqItem(19639, 0.47, -9.5)],
  '水月雨 SSP'
)

const Moondrop_SSR: ParametricEQ = new ParametricEQ(
  BAND.MOONDROP, 'Moondrop SSR', 'Crinacle', -6.7,
  [new EqItem(33, 0.48, 6.5), new EqItem(834, 1.7, 2.6), new EqItem(3119, 2.38, -3.7),
    new EqItem(10515, 1.73, 3.1), new EqItem(19639, 0.38, -11.7), new EqItem(59, 3.62, 0.7),
    new EqItem(230, 2.03, -1.1), new EqItem(6283, 2.67, -2.2), new EqItem(6533, 1.08, 1.1),
    new EqItem(13993, 2.44, 0.7)],
  '水月雨 SSR'
)

const Moondrop_Starfield: ParametricEQ = new ParametricEQ(
  BAND.MOONDROP, 'Moondrop Starfield', 'Crinacle', -6.8,
  [new EqItem(89, 0.51, -2.6), new EqItem(228, 1.38, -1.7), new EqItem(1879, 1.61, -2.7),
    new EqItem(3690, 1.2, 2.5), new EqItem(8083, 1.46, 6.3), new EqItem(348, 2.75, -0.3),
    new EqItem(805, 2.74, 1.2), new EqItem(6170, 6.8, 1.2), new EqItem(11720, 1.59, 3.2),
    new EqItem(19705, 0.44, -11.7)],
  '水月雨 星野'
)

const NiceHCK_Vido: ParametricEQ = new ParametricEQ(
  BAND.NICEHCK, 'NiceHCK Vido', 'Reference Audio Analyzer', -6.9,
  [new EqItem(31, 0.69, 6.6), new EqItem(1595, 1.01, -15.5), new EqItem(3545, 2.61, 4.6),
    new EqItem(5824, 1.81, -11.3), new EqItem(6699, 0.06, 7.2), new EqItem(52, 4.15, 2.0),
    new EqItem(85, 2.7, -1.7), new EqItem(719, 1.1, -2.7), new EqItem(727, 2.46, 4.8),
    new EqItem(9328, 5.82, 1.6)],
  '原道'
)

const OnePlus_Buds: ParametricEQ = new ParametricEQ(
  BAND.ONEPLUS, 'OnePlus Buds', 'Rtings', -6.7,
  [new EqItem(36, 0.39, 6.5), new EqItem(324, 2.51, 2.6), new EqItem(1607, 2.71, -4.7),
    new EqItem(7207, 2.41, -4.8), new EqItem(17697, 0.32, 6.6), new EqItem(913, 4.93, 1.4),
    new EqItem(3798, 4.71, 1.2), new EqItem(8081, 3.48, 1.8), new EqItem(9725, 1.21, -1.8),
    new EqItem(13188, 2.65, 1.9)]
)

const OnePlus_Buds_Z: ParametricEQ = new ParametricEQ(
  BAND.ONEPLUS, 'OnePlus Buds Z', 'Rtings', -5.7,
  [new EqItem(30, 0.16, -11.8), new EqItem(2027, 1.02, 5.0), new EqItem(3572, 2.34, 3.1),
    new EqItem(8321, 1.81, 4.2), new EqItem(11906, 1.45, 2.8), new EqItem(122, 3.24, 1.1),
    new EqItem(519, 2.78, -1.4), new EqItem(4283, 4.8, 1.5), new EqItem(5179, 3.56, -2.8),
    new EqItem(6192, 5.96, 2.4)]
)

const OPPO_Enco_X: ParametricEQ = new ParametricEQ(
  BAND.OPPO, 'OPPO Enco X', 'oratory1990', -3.4,
  [new EqItem(16, 1.02, -1.7), new EqItem(111, 0.37, -4.5), new EqItem(216, 1.29, 5.2),
    new EqItem(2273, 1.45, 3.6), new EqItem(20114, 0.18, -7.4), new EqItem(2300, 4.37, -0.4),
    new EqItem(4217, 1.92, 2.4), new EqItem(5695, 2.07, -5.6), new EqItem(9605, 0.84, 1.4)]
)

const OPPO_Enco_X2: ParametricEQ = new ParametricEQ(
  BAND.OPPO, 'OPPO Enco X2', 'Moriafly', -5.9,
  [new EqItem(160, 2.9, 2.7), new EqItem(50, 3.1, 1), new EqItem(890, 3.69, 3.1),
    new EqItem(1790, 2.15, 5.2), new EqItem(1420, 1.4, -3.0), new EqItem(2408, 3.1, -1.2),
    new EqItem(9100, 3.37, -1.9), new EqItem(15000, 1.9, 1.1)],
  '椒盐自调'
)

const QCY_T1C: ParametricEQ = new ParametricEQ(
  BAND.QCY, 'QCY T1C', 'Reference Audio Analyzer', -6.3,
  [new EqItem(12, 0.76, -15.3), new EqItem(40, 0.32, -8.6), new EqItem(264, 0.9, -3.1),
    new EqItem(4925, 0.85, 6.5), new EqItem(19909, 0.35, 4.2), new EqItem(2362, 2.94, -1.3),
    new EqItem(3342, 1.52, 1.2), new EqItem(4898, 2.51, -1.1), new EqItem(6841, 4.09, 1.5),
    new EqItem(8380, 3.03, -0.9)]
)

const QCY_T5_Pro: ParametricEQ = new ParametricEQ(
  BAND.QCY, 'QCY T5 Pro', 'Reference Audio Analyzer', -7.2,
  [new EqItem(20, 0.78, -2.5), new EqItem(61, 0.8, -2.8), new EqItem(192, 0.67, -5.4),
    new EqItem(4473, 1.26, 6.4), new EqItem(17755, 0.53, 6.9), new EqItem(2491, 0.85, 1.8),
    new EqItem(2809, 3.64, -2.7), new EqItem(6179, 3.68, 3.9), new EqItem(7920, 0.86, -3.0),
    new EqItem(13267, 2.27, 2.9)]
)

const Samsung_EO_IG955_AKG: ParametricEQ = new ParametricEQ(
  BAND.SAMSUNG, 'Samsung EO-IG955 (AKG)', 'Crinacle', -6.7,
  [new EqItem(55, 0.39, -3.6), new EqItem(174, 0.48, -3.6), new EqItem(832, 0.95, 3.6),
    new EqItem(4625, 3.37, 3.5), new EqItem(6551, 3.03, 6.0), new EqItem(2142, 5.38, 0.6),
    new EqItem(8629, 2.27, 1.7), new EqItem(10009, 0.92, 1.3), new EqItem(19615, 0.27, -9.7)]
)

const Samsung_Galaxy_Buds: ParametricEQ = new ParametricEQ(
  BAND.SAMSUNG, 'Samsung Galaxy Buds', 'oratory1990', -6.8,
  [new EqItem(67, 1.17, -1.8), new EqItem(280, 1.02, -1.6), new EqItem(4236, 3.23, 3.1),
    new EqItem(14217, 2.00, 4.1), new EqItem(18824, 0.57, 6.3), new EqItem(18, 2.22, 1.2),
    new EqItem(1491, 3.43, -0.7), new EqItem(6613, 4.82, -3.1), new EqItem(7541, 1.82, 2.4),
    new EqItem(9931, 3.79, -2.5)]
)

const Samsung_Galaxy_Buds2: ParametricEQ = new ParametricEQ(
  BAND.SAMSUNG, 'Samsung Galaxy Buds2', 'Crinacle', -6.3,
  [new EqItem(15, 0.86, -1.7), new EqItem(66, 0.47, -3.7), new EqItem(355, 1.43, -1.2),
    new EqItem(4286, 1.58, 6.0), new EqItem(10691, 2.77, 2.5), new EqItem(980, 2.92, 1.1),
    new EqItem(1454, 3.46, -1.4), new EqItem(5577, 4.15, 1.6), new EqItem(6990, 2.66, -1.9),
    new EqItem(9094, 4.15, 1.0)]
)

const Samsung_Galaxy_Buds_Live: ParametricEQ = new ParametricEQ(
  BAND.SAMSUNG, 'Samsung Galaxy Buds Live', 'Rtings', -6.8,
  [new EqItem(72, 0.63, -8.2), new EqItem(1714, 2.55, 4.6), new EqItem(4569, 2.61, 5.7),
    new EqItem(16895, 1.75, 3.3), new EqItem(19400, 1, 6.2), new EqItem(524, 1.29, -5.6),
    new EqItem(555, 0.53, 2.8), new EqItem(2794, 4.73, -3.2), new EqItem(3560, 4.36, 1.9),
    new EqItem(6753, 7.61, -3.0)]
)

const Samsung_Galaxy_Buds_Pro: ParametricEQ = new ParametricEQ(
  BAND.SAMSUNG, 'Samsung Galaxy Buds Pro', 'Crinacle', -3.1,
  [new EqItem(52, 0.36, -1.2), new EqItem(162, 0.24, -2.8), new EqItem(1153, 0.77, 2.3),
    new EqItem(3985, 1.61, 2.6), new EqItem(8394, 4.18, 2.1), new EqItem(10325, 1, 2.3),
    new EqItem(19794, 0.33, -10.5)]
)

const Samsung_Galaxy_Buds_Add: ParametricEQ = new ParametricEQ(
  BAND.SAMSUNG, 'Samsung Galaxy Buds+', 'Rtings', -4.0,
  [new EqItem(30, 0.66, -2.6), new EqItem(69, 1.05, -2.4), new EqItem(306, 2.03, -1.1),
    new EqItem(5105, 2.42, 0.4), new EqItem(10191, 0.85, 3.2), new EqItem(844, 2.82, 1.1),
    new EqItem(1284, 2.81, -1.4), new EqItem(5749, 4.5, 1.9), new EqItem(6702, 3.25, -2.8),
    new EqItem(8104, 4.3, 2.0)]
)

const Sennheiser_IE_60: ParametricEQ = new ParametricEQ(
  BAND.SENNHEISER, 'Sennheiser IE 60', 'Reference Audio Analyzer', -6.4,
  [new EqItem(18, 0.75, 5.6), new EqItem(196, 0.41, -6.5), new EqItem(2710, 0.38, 7.5),
    new EqItem(6506, 2.1, -12.9), new EqItem(11116, 3.09, 1.9), new EqItem(2491, 3.52, -0.7),
    new EqItem(4876, 3.79, 2.4), new EqItem(5625, 5.49, -2.3), new EqItem(13541, 1.87, 1.2),
    new EqItem(19850, 0.53, -5.2)]
)

const Simgot_Audio_EM2: ParametricEQ = new ParametricEQ(
  BAND.SIMGOT, 'Simgot Audio EM2', 'Reference Audio Analyzer', -6.6,
  [new EqItem(518, 0.21, -4.5), new EqItem(854, 0.59, 5.1), new EqItem(3844, 3.2, 4.8),
    new EqItem(9010, 1.39, 4.7), new EqItem(14093, 0.99, 5.6), new EqItem(4483, 5.14, 1.3),
    new EqItem(5261, 2.94, -1.7), new EqItem(6361, 6.2, 1.6), new EqItem(16810, 1.84, 0.7),
    new EqItem(19920, 1.02, -2.2)]
)

const Sony_MDR_EX15LP: ParametricEQ = new ParametricEQ(
  BAND.SONY, 'Sony MDR-EX15LP', 'Reference Audio Analyzer', -7.0,
  [new EqItem(15, 0.33, 3.6), new EqItem(111, 1.12, -1.3), new EqItem(265, 1.44, -2.1),
    new EqItem(1969, 5.65, 2.0), new EqItem(9408, 1.62, 6.7), new EqItem(4403, 1.63, -2.0),
    new EqItem(5823, 3.3, 1.0), new EqItem(6354, 2.15, 1.1), new EqItem(12857, 1.71, 3.0),
    new EqItem(19790, 0.52, -10.4)]
)

const Sony_WF_1000XM3: ParametricEQ = new ParametricEQ(
  BAND.SONY, 'Sony WF-1000XM3', 'Crinacle', -5.4,
  [new EqItem(102, 0.95, -3.0), new EqItem(250, 0.48, -3.7), new EqItem(819, 0.72, 2.4),
    new EqItem(4736, 1.24, 5.0), new EqItem(7964, 2.86, 2.4), new EqItem(17, 1.81, 1.3),
    new EqItem(1350, 5.11, -0.8), new EqItem(2237, 3.27, 0.7), new EqItem(9619, 1.23, 1.5),
    new EqItem(19529, 0.37, -7.8)],
  '优化版'
)

const Sony_WF_1000XM4: ParametricEQ = new ParametricEQ(
  BAND.SONY, 'Sony WF-1000XM4', 'Crinacle', -6.9,
  [new EqItem(47, 0.47, -1.6), new EqItem(151, 0.44, -3.4), new EqItem(449, 1.19, -1.8),
    new EqItem(4876, 0.9, 5.1), new EqItem(8416, 2.13, 4.4), new EqItem(1857, 2.2, 0.4),
    new EqItem(11274, 1.75, 1.9), new EqItem(11332, 0.64, 0.9), new EqItem(19375, 0.36, -6.3),
    new EqItem(19798, 0.46, -5.8)]
)

const Sony_WH_1000XM3: ParametricEQ = new ParametricEQ(
  BAND.SONY, 'Sony WH-1000XM3', 'oratory1990', -5.5,
  [new EqItem(24, 0.47, -5.7), new EqItem(121, 0.64, -6.5), new EqItem(1503, 1.64, 5.3),
    new EqItem(4160, 1.62, 4.2), new EqItem(19453, 0.25, 2.2), new EqItem(547, 2.1, -3.5),
    new EqItem(674, 0.72, 2.5), new EqItem(818, 2.82, -2.8), new EqItem(1605, 4.95, -2.4),
    new EqItem(1722, 2.75, 0.9)]
)

const Sony_WH_H900N: ParametricEQ = new ParametricEQ(
  BAND.SONY, 'Sony WH-H900N', 'oratory1990', -6.9,
  [new EqItem(50, 0.29, -2.0), new EqItem(176, 0.7, -3.3), new EqItem(2535, 2.41, 6.3),
    new EqItem(10452, 0.51, 1.6), new EqItem(22049, 1.96, 1.4), new EqItem(805, 10.3, 1.4),
    new EqItem(3747, 6.1, 1.9), new EqItem(4071, 5.76, -4.1), new EqItem(5260, 1.94, 2.2),
    new EqItem(6479, 6.09, -3.4)]
)

const Sony_WH_H910N: ParametricEQ = new ParametricEQ(
  BAND.SONY, 'Sony WH-H910N', 'Rtings', -6.3,
  [new EqItem(33, 0.71, -4.0), new EqItem(153, 1.58, -5.4), new EqItem(3746, 1.22, 8.6),
    new EqItem(4714, 2.35, -11.4), new EqItem(10407, 1.8, 5.0), new EqItem(661, 2.47, 3.2),
    new EqItem(1437, 0.77, -2.2), new EqItem(1863, 1.65, 3.4), new EqItem(2752, 5.78, -4.4),
    new EqItem(3120, 5.25, 2.5)]
)

const TFZ_Mylove_2: ParametricEQ = new ParametricEQ(
  BAND.TFZ, 'TFZ Mylove 2', 'Crinacle', -6.8,
  [new EqItem(15, 0.09, -5.4), new EqItem(701, 1.51, 2.7), new EqItem(3412, 4.73, 3.9),
    new EqItem(11433, 1.38, 4.0), new EqItem(18103, 0.44, 6.0), new EqItem(1997, 1.49, -4.2),
    new EqItem(2828, 0.48, 2.2), new EqItem(4877, 4.38, -4.4), new EqItem(6169, 3.79, 2.5),
    new EqItem(7141, 4.72, -3.3)],
  '锦瑟香也'
)

const VSonic_GR07: ParametricEQ = new ParametricEQ(
  BAND.VSONIC, 'VSonic GR07', 'Crinacle', -6.0,
  [new EqItem(14, 0.4, 5.1), new EqItem(256, 0.45, -3.3), new EqItem(3939, 0.81, 6.4),
    new EqItem(5978, 2.85, -5.5), new EqItem(10546, 1.9, 5.2), new EqItem(1374, 2.87, -1.6),
    new EqItem(2327, 0.61, 1.2), new EqItem(3086, 1.99, -1.3), new EqItem(19520, 0.97, -8.8)]
)

const Whizzer_HE01: ParametricEQ = new ParametricEQ(
  BAND.WHIZZER, 'Whizzer HE01', 'Crinacle', -6.5,
  [new EqItem(85, 0.78, -2.7), new EqItem(201, 0.84, -3.2), new EqItem(813, 2.04, 2.6),
    new EqItem(7533, 1.16, 7.2), new EqItem(19335, 0.52, -9.5), new EqItem(12, 1.46, 0.9),
    new EqItem(4667, 0.64, -2.1), new EqItem(5498, 3.54, 4.0), new EqItem(7788, 3.33, -1.1),
    new EqItem(9688, 1.07, 1.6)]
)

// 获取所有 AutoEQ 预设（与 Android getAllAutoEq() 顺序一致）
export function getAllAutoEq(): ParametricEQ[] {
  return [
    NONE_Original,
    Mega_bass,
    Clear,
    Clear_V2,
    AKG_K240_MKII,
    Apple_AirPods,
    Apple_AirPods_Max,
    Apple_AirPods_Pro,
    Beats_Pro,
    Bose_QuietComfort_35_II,
    Google_Pixel_Buds_2,
    HZSOUND_Heart_Mirror,
    Moondrop_Quarks,
    Moondrop_Spaceship,
    Moondrop_SSP,
    Moondrop_SSR,
    Moondrop_Starfield,
    NiceHCK_Vido,
    OnePlus_Buds,
    OnePlus_Buds_Z,
    OPPO_Enco_X,
    OPPO_Enco_X2,
    QCY_T1C,
    QCY_T5_Pro,
    Samsung_EO_IG955_AKG,
    Samsung_Galaxy_Buds,
    Samsung_Galaxy_Buds2,
    Samsung_Galaxy_Buds_Live,
    Samsung_Galaxy_Buds_Pro,
    Samsung_Galaxy_Buds_Add,
    Sennheiser_IE_60,
    Simgot_Audio_EM2,
    Sony_MDR_EX15LP,
    Sony_WF_1000XM3,
    Sony_WF_1000XM4,
    Sony_WH_1000XM3,
    Sony_WH_H900N,
    Sony_WH_H910N,
    TFZ_Mylove_2,
    VSonic_GR07,
    Whizzer_HE01
  ]
}

// 根据 BAND 获取对应图标资源
export function getBandIcon(band: BAND): Resource {
  switch (band) {
    case BAND.NONE: return $r('app.media.ic_salt_player_audio_fx')
    case BAND.AKG: return $r('app.media.ic_akg')
    case BAND.APPLE: return $r('app.media.ic_apple')
    case BAND.BEATS: return $r('app.media.ic_beats')
    case BAND.BOSE: return $r('app.media.ic_bose')
    case BAND.GOOGLE: return $r('app.media.ic_google')
    case BAND.MOONDROP: return $r('app.media.ic_moondrop')
    case BAND.ONEPLUS: return $r('app.media.ic_oneplus')
    case BAND.OPPO: return $r('app.media.ic_oppo')
    case BAND.QCY: return $r('app.media.ic_qcy')
    case BAND.SAMSUNG: return $r('app.media.ic_samsung')
    case BAND.SENNHEISER: return $r('app.media.ic_sennheiser')
    case BAND.SONY: return $r('app.media.ic_sony')
    case BAND.TFZ: return $r('app.media.tfz')
    case BAND.VSONIC: return $r('app.media.ic_vsonic')
    default: return $r('app.media.ic_salt_player_audio_fx')
  }
}

// AutoEQ 预设：内置多款耳机参数均衡曲线数据。
