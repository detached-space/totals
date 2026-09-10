import { readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const OVERTURE_RELEASE = '2026-07-22.0';
const ADDIS_SUBCITY_WFS =
  'https://geos.addiscadaster.gov.et/geoserver/ncrprs_cadaster/ows' +
  '?service=WFS&version=2.0.0&request=GetFeature' +
  '&typeNames=ncrprs_cadaster%3ASubcity_Boundary' +
  '&outputFormat=application%2Fjson&srsName=EPSG%3A4326';

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const defaultOutputPath = resolve(
  scriptDirectory,
  '../assets/maps/ethiopia_city_places.json',
);

const cityRecords = [
  city(
    'addis_ababa',
    'Addis Ababa',
    'አዲስ አበባ',
    9.0358119,
    38.7524315,
    28,
    'overture_divisions',
    '3d7cc12f-9bf1-4b56-bfdc-63ebaaf785af',
  ),
  city(
    'adama',
    'Adama',
    'አዳማ',
    8.5410261,
    39.2705461,
    25,
    'overture_divisions',
    '21464a32-a633-42c3-899e-59fa49fce407',
  ),
  city(
    'bahir_dar',
    'Bahir Dar',
    'ባሕር-ዳር',
    11.5949663,
    37.3882251,
    24,
    'overture_divisions',
    'f4871905-f041-44a0-86df-7ee580e7a6c2',
  ),
  city(
    'bishoftu',
    'Bishoftu',
    'ቢሾፍቱ',
    8.750004,
    38.981734,
    18,
    'overture_divisions',
    'f6ea605b-b943-46cc-bf15-5e0643bbfe00',
  ),
  city(
    'dire_dawa',
    'Dire Dawa',
    'ድሬዳዋ',
    9.591323,
    41.8566341,
    25,
    'overture_divisions',
    'ddac3315-ff32-4a28-9a3c-aeb42b17d28d',
  ),
  city(
    'hawassa',
    'Hawassa',
    'አዋሳ',
    7.0481029,
    38.47861,
    24,
    'overture_divisions',
    'eea38351-0b2d-4f84-9b7c-4e863f262fea',
  ),
  city(
    'gondar',
    'Gondar',
    'ጎንደር',
    12.610368,
    37.466766,
    24,
    'overture_divisions',
    '00bf2c7e-b1e4-4c25-af5a-a31c7b55690a',
  ),
  city(
    'mekelle',
    'Mekelle',
    'መቀለ',
    13.4966644,
    39.4768259,
    25,
    'overture_divisions',
    '92786cad-c371-4640-829e-a07d7b6ebd2f',
  ),
  city(
    'jimma',
    'Jimma',
    'ጂማ',
    7.6756152,
    36.8478779,
    22,
    'overture_divisions',
    '992f5174-5cde-4336-be94-1b6e7b7e7bca',
  ),
  city(
    'dessie',
    'Dessie',
    'ደሴ',
    11.122604,
    39.634982,
    20,
    'overture_divisions',
    '0392e899-ae0c-487f-95c0-eb0306ae6458',
  ),
  city(
    'harar',
    'Harar',
    'ሐረር',
    9.3118304,
    42.1284009,
    18,
    'overture_divisions',
    '4a9d9cb1-96b4-4a44-933b-6ab281f789f4',
  ),
  city(
    'jigjiga',
    'Jigjiga',
    'ጂጂጋ',
    9.3508526,
    42.8003788,
    24,
    'overture_divisions',
    'bfbc0cd1-d919-4c5a-b646-8cb24344643f',
  ),
  city(
    'arba_minch',
    'Arba Minch',
    'አርባ ምንጭ',
    6.0215142,
    37.5539809,
    20,
    'overture_divisions',
    'a6ccb45a-402b-4a8a-9d61-e3a74a4f0a2a',
  ),
  // Overture Divisions currently has no Shashamane locality record. This
  // anchor uses a high-confidence Overture Places record in the city center.
  city(
    'shashamane',
    'Shashamane',
    'ሻሸመኔ',
    7.193602,
    38.593124,
    18,
    'overture_places',
    'de9e621a-e00a-4f90-a31b-128ec8b798a0',
  ),
  city(
    'debre_birhan',
    'Debre Birhan',
    'ደብረ ብርሃን',
    9.6752117,
    39.5324899,
    18,
    'overture_divisions',
    '11a12a5b-8ce7-41b6-86dc-c467afe229fa',
  ),
  city(
    'kombolcha',
    'Kombolcha',
    'ኮምቦልቻ',
    11.0813583,
    39.7408732,
    18,
    'overture_divisions',
    'd4fc165a-a0d7-4084-8abd-abca63f548e0',
  ),
  city(
    'nekemte',
    'Nekemte',
    'ነቀምት',
    9.0905237,
    36.5481573,
    20,
    'overture_divisions',
    '83f9087d-09f1-435f-8fd7-8745d5d9f4de',
  ),
  city(
    'asella',
    'Asella',
    'አሰላ',
    7.95,
    39.13333,
    18,
    'overture_divisions',
    'd0752667-4128-408e-a343-07128b511438',
  ),
  city(
    'axum',
    'Axum',
    'አክሱም',
    14.1220982,
    38.7321749,
    18,
    'overture_divisions',
    '9e69277f-e9f9-4f59-850a-b081173a4562',
  ),
  city(
    'lalibela',
    'Lalibela',
    'ላሊበላ',
    12.0360639,
    39.0456845,
    18,
    'overture_divisions',
    '6936c59a-b7a5-4dd8-b572-bbae5f4ed2f9',
  ),
  city(
    'semera',
    'Semera',
    'ሰመራ',
    11.7923098,
    41.0089155,
    24,
    'overture_divisions',
    '48bbdc00-3b4d-4d70-a558-73a6305674ef',
  ),
  city(
    'gambela',
    'Gambela',
    'ጋምቤላ',
    8.2503656,
    34.5877344,
    22,
    'overture_divisions',
    '17ae8ec7-0903-430f-9cb2-01413ebc2d80',
  ),
  city(
    'assosa',
    'Assosa',
    'አሶሳ',
    10.0646352,
    34.5437024,
    20,
    'overture_divisions',
    '6ba11aad-dab1-4219-a08f-3d1687199bf5',
  ),
];

const subcityNames = new Map([
  ['Nifas Silk Lafto', ['Nifas Silk Lafto', 'ንፋስ ስልክ ላፍቶ']],
  ['Bole', ['Bole', 'ቦሌ']],
  ['Kirkos', ['Kirkos', 'ቂርቆስ']],
  ['Lideta', ['Lideta', 'ልደታ']],
  ['Arada', ['Arada', 'አራዳ']],
  ['Addis Ketema', ['Addis Ketema', 'አዲስ ከተማ']],
  ['Yeka', ['Yeka', 'የካ']],
  ['Akaki Kality', ['Akaki Kality', 'አቃቂ ቃሊቲ']],
  ['Kolfe Keraniyo', ['Kolfe Keraniyo', 'ቆልፌ ቀራኒዮ']],
  ['Lemi Kura', ['Lemi Kura', 'ለሚ ኩራ']],
  ['Gulele', ['Gulele', 'ጉለሌ']],
]);

function city(
  cityId,
  name,
  nameAm,
  latitude,
  longitude,
  matchRadiusKm,
  sourceId,
  sourceRecordId,
) {
  return {
    sourceId,
    sourceRecordId,
    cityId,
    type: 'city',
    name,
    nameEn: name,
    nameAm,
    latitude,
    longitude,
    matchRadiusKm,
  };
}

function normalizedName(value) {
  return String(value).trim().replace(/\s+/g, ' ');
}

function polygonCenter(multiPolygon) {
  let weightedLongitude = 0;
  let weightedLatitude = 0;
  let totalWeight = 0;

  for (const polygon of multiPolygon) {
    const ring = polygon[0];
    let twiceArea = 0;
    let longitudeSum = 0;
    let latitudeSum = 0;
    for (let index = 0; index < ring.length - 1; index += 1) {
      const [firstLongitude, firstLatitude] = ring[index];
      const [secondLongitude, secondLatitude] = ring[index + 1];
      const cross =
        firstLongitude * secondLatitude - secondLongitude * firstLatitude;
      twiceArea += cross;
      longitudeSum += (firstLongitude + secondLongitude) * cross;
      latitudeSum += (firstLatitude + secondLatitude) * cross;
    }

    const weight = Math.abs(twiceArea);
    if (weight <= Number.EPSILON) continue;
    weightedLongitude += (longitudeSum / (3 * twiceArea)) * weight;
    weightedLatitude += (latitudeSum / (3 * twiceArea)) * weight;
    totalWeight += weight;
  }

  if (totalWeight <= Number.EPSILON) {
    throw new Error('Subcity geometry has no measurable polygon area.');
  }
  return {
    longitude: weightedLongitude / totalWeight,
    latitude: weightedLatitude / totalWeight,
  };
}

async function loadSubcities(sourcePath) {
  if (sourcePath) {
    return {
      geoJson: JSON.parse(await readFile(resolve(sourcePath), 'utf8')),
      dataTimestamp: new Date().toISOString(),
    };
  }

  const response = await fetch(ADDIS_SUBCITY_WFS);
  if (!response.ok) {
    throw new Error(`Addis subcity WFS returned HTTP ${response.status}.`);
  }
  const responseDate = response.headers.get('date');
  return {
    geoJson: await response.json(),
    dataTimestamp: responseDate
      ? new Date(responseDate).toISOString()
      : new Date().toISOString(),
  };
}

function parseArguments(argumentsList) {
  let sourcePath;
  let outputPath = defaultOutputPath;
  for (let index = 0; index < argumentsList.length; index += 1) {
    const argument = argumentsList[index];
    if (argument === '--source') {
      sourcePath = argumentsList[++index];
    } else if (argument === '--output') {
      outputPath = resolve(argumentsList[++index]);
    } else {
      throw new Error(`Unknown argument: ${argument}`);
    }
  }
  return { sourcePath, outputPath };
}

const { sourcePath, outputPath } = parseArguments(process.argv.slice(2));
const { geoJson, dataTimestamp } = await loadSubcities(sourcePath);
if (geoJson.type !== 'FeatureCollection' || !Array.isArray(geoJson.features)) {
  throw new Error('Expected an Addis subcity GeoJSON FeatureCollection.');
}

const seenSubcities = new Set();
const subcityRecords = geoJson.features.map((feature) => {
  const sourceName = normalizedName(feature.properties?.Sub_City);
  const names = subcityNames.get(sourceName);
  if (!names) throw new Error(`Unexpected Addis subcity: ${sourceName}`);
  if (!feature.id || !feature.geometry) {
    throw new Error(`Incomplete Addis subcity feature: ${sourceName}`);
  }
  if (feature.geometry.type !== 'MultiPolygon') {
    throw new Error(`Expected MultiPolygon geometry for ${sourceName}.`);
  }
  if (seenSubcities.has(sourceName)) {
    throw new Error(`Duplicate Addis subcity: ${sourceName}`);
  }
  seenSubcities.add(sourceName);
  const center = polygonCenter(feature.geometry.coordinates);
  return {
    sourceId: 'addis_cadastre',
    sourceRecordId: feature.id,
    cityId: 'addis_ababa',
    type: 'subcity',
    name: names[0],
    nameEn: names[0],
    nameAm: names[1],
    latitude: center.latitude,
    longitude: center.longitude,
    polygons: feature.geometry.coordinates,
  };
});

if (seenSubcities.size !== subcityNames.size) {
  const missing = [...subcityNames.keys()].filter(
    (name) => !seenSubcities.has(name),
  );
  throw new Error(`Missing Addis subcities: ${missing.join(', ')}`);
}

const asset = {
  schemaVersion: 3,
  detailedCityId: 'addis_ababa',
  sources: [
    {
      id: 'overture_divisions',
      name: 'Overture Maps Divisions',
      attribution: '© OpenStreetMap contributors, Overture Maps Foundation',
      license: 'Open Database License (ODbL) 1.0',
      licenseUrl: 'https://docs.overturemaps.org/attribution/',
      dataTimestamp: `${OVERTURE_RELEASE.slice(0, 10)}T00:00:00Z`,
    },
    {
      id: 'overture_places',
      name: 'Overture Maps Places',
      attribution: 'Overture Maps Foundation; data from Meta',
      license: 'Community Data License Agreement - Permissive 2.0',
      licenseUrl: 'https://docs.overturemaps.org/attribution/',
      dataTimestamp: `${OVERTURE_RELEASE.slice(0, 10)}T00:00:00Z`,
    },
    {
      id: 'addis_cadastre',
      name: 'Addis Ababa Cadaster',
      attribution: 'Addis Ababa City Administration',
      license: 'Public WFS (fees: none; access constraints: none)',
      licenseUrl:
        'https://geos.addiscadaster.gov.et/geoserver/ncrprs_cadaster/ows' +
        '?service=WFS&version=2.0.0&request=GetCapabilities',
      dataTimestamp,
    },
  ],
  bounds: {
    south: 3,
    west: 32.5,
    north: 15.5,
    east: 48.5,
  },
  cities: cityRecords.map((record) => ({
    id: record.cityId,
    name: record.name,
    subcityRecordCount: record.cityId === 'addis_ababa' ? 11 : 0,
  })),
  places: [...cityRecords, ...subcityRecords],
};

await writeFile(outputPath, `${JSON.stringify(asset)}\n`, 'utf8');
console.log(
  `Wrote ${asset.places.length} records (${subcityRecords.length} Addis ` +
    `subcities) to ${outputPath}`,
);
