import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();
const db = prisma as any;

const catalog: Record<string, string[]> = {
    'Acura': ['ILX', 'Integra', 'MDX', 'RDX', 'TLX'],
    'Alfa Romeo': ['Giulia', 'Giulietta', 'Stelvio', 'Tonale'],
    'Audi': ['A3', 'A4', 'A5', 'A6', 'A7', 'A8', 'Q3', 'Q5', 'Q7', 'Q8', 'e-tron'],
    'Bentley': ['Bentayga', 'Continental GT', 'Flying Spur'],
    'BMW': ['1 Series', '3 Series', '5 Series', '7 Series', 'X1', 'X3', 'X5', 'X6', 'X7', 'i4', 'iX'],
    'BYD': ['Atto 3', 'Dolphin', 'Han', 'Seal', 'Song Plus', 'Tang'],
    'Cadillac': ['CT5', 'Escalade', 'XT4', 'XT5', 'XT6'],
    'Changan': ['Alsvin', 'CS35 Plus', 'CS55 Plus', 'CS75 Plus', 'UNI-K', 'UNI-T', 'UNI-V'],
    'Chery': ['Arrizo 8', 'Tiggo 4 Pro', 'Tiggo 7 Pro', 'Tiggo 8 Pro', 'Tiggo 9'],
    'Chevrolet': ['Aveo', 'Captiva', 'Cobalt', 'Cruze', 'Epica', 'Equinox', 'Lacetti', 'Malibu', 'Nexia', 'Tahoe', 'Tracker', 'Trailblazer'],
    'Citroen': ['Berlingo', 'C3', 'C4', 'C5 Aircross'],
    'Daewoo': ['Gentra', 'Matiz', 'Nexia'],
    'Dodge': ['Challenger', 'Charger', 'Durango', 'Journey'],
    'Exeed': ['LX', 'RX', 'TXL', 'VX'],
    'FAW': ['Bestune B70', 'Bestune T77', 'Bestune T99'],
    'Ferrari': ['296', '812', 'F8', 'Portofino', 'Roma'],
    'Fiat': ['500', 'Doblo', 'Ducato', 'Tipo'],
    'Ford': ['Bronco', 'EcoSport', 'Edge', 'Escape', 'Explorer', 'F-150', 'Fiesta', 'Focus', 'Fusion', 'Kuga', 'Mondeo', 'Mustang', 'Transit'],
    'GAC': ['GS3', 'GS4', 'GS5', 'GS8', 'M8'],
    'GAZ': ['Gazelle', 'Sobol', 'Volga'],
    'Geely': ['Atlas', 'Coolray', 'Emgrand', 'Monjaro', 'Okavango', 'Tugella'],
    'Genesis': ['G70', 'G80', 'G90', 'GV70', 'GV80'],
    'Great Wall': ['Poer', 'Wingle'],
    'Haval': ['Dargo', 'F7', 'H6', 'Jolion', 'M6'],
    'Honda': ['Accord', 'Civic', 'CR-V', 'Fit', 'HR-V', 'Odyssey', 'Pilot'],
    'Hongqi': ['E-HS9', 'H5', 'H9', 'HS5', 'HS7'],
    'Hyundai': ['Accent', 'Avante', 'Creta', 'Elantra', 'Genesis', 'Grandeur', 'H-1', 'i30', 'Palisade', 'Santa Fe', 'Solaris', 'Sonata', 'Staria', 'Tucson'],
    'Infiniti': ['EX', 'FX', 'Q50', 'QX50', 'QX55', 'QX60', 'QX70', 'QX80'],
    'JAC': ['J7', 'JS4', 'JS6', 'S3', 'S5', 'T6', 'T8'],
    'Jaecoo': ['J7', 'J8'],
    'Jaguar': ['E-Pace', 'F-Pace', 'I-Pace', 'XE', 'XF'],
    'Jeep': ['Cherokee', 'Compass', 'Grand Cherokee', 'Renegade', 'Wrangler'],
    'Jetour': ['Dashing', 'T2', 'X70', 'X90'],
    'Kia': ['Carnival', 'Ceed', 'Cerato', 'K5', 'K7', 'Mohave', 'Optima', 'Picanto', 'Rio', 'Seltos', 'Sorento', 'Soul', 'Sportage', 'Stinger'],
    'Lada': ['Granta', 'Kalina', 'Largus', 'Niva', 'Priora', 'Vesta', 'XRAY'],
    'Lamborghini': ['Aventador', 'Huracan', 'Urus'],
    'Land Rover': ['Defender', 'Discovery', 'Discovery Sport', 'Range Rover', 'Range Rover Evoque', 'Range Rover Sport', 'Range Rover Velar'],
    'Lexus': ['ES', 'GS', 'GX', 'IS', 'LS', 'LX', 'NX', 'RX', 'UX'],
    'Li Auto': ['L6', 'L7', 'L8', 'L9', 'Mega'],
    'Maserati': ['Ghibli', 'Grecale', 'Levante', 'Quattroporte'],
    'Mazda': ['2', '3', '5', '6', 'CX-3', 'CX-30', 'CX-5', 'CX-7', 'CX-9', 'CX-90'],
    'Mercedes-Benz': ['A-Class', 'C-Class', 'CLA', 'CLS', 'E-Class', 'G-Class', 'GLA', 'GLB', 'GLC', 'GLE', 'GLS', 'S-Class', 'V-Class', 'Vito'],
    'MINI': ['Clubman', 'Cooper', 'Countryman'],
    'Mitsubishi': ['ASX', 'Eclipse Cross', 'Galant', 'L200', 'Lancer', 'Montero', 'Outlander', 'Pajero', 'Pajero Sport'],
    'Nissan': ['Almera', 'Altima', 'Juke', 'Maxima', 'Murano', 'Pathfinder', 'Patrol', 'Qashqai', 'Sentra', 'Teana', 'Terrano', 'Tiida', 'X-Trail'],
    'Omoda': ['C5', 'S5'],
    'Opel': ['Antara', 'Astra', 'Corsa', 'Insignia', 'Mokka', 'Vectra', 'Zafira'],
    'Peugeot': ['2008', '3008', '301', '308', '408', '5008', 'Partner'],
    'Porsche': ['911', 'Cayenne', 'Macan', 'Panamera', 'Taycan'],
    'Ravon': ['Gentra', 'Nexia R3', 'R2', 'R4'],
    'Renault': ['Arkana', 'Duster', 'Fluence', 'Kaptur', 'Koleos', 'Logan', 'Megane', 'Sandero'],
    'Rolls-Royce': ['Cullinan', 'Ghost', 'Phantom', 'Wraith'],
    'Skoda': ['Fabia', 'Karoq', 'Kodiaq', 'Octavia', 'Rapid', 'Superb', 'Yeti'],
    'Subaru': ['Forester', 'Impreza', 'Legacy', 'Outback', 'Tribeca', 'XV'],
    'Suzuki': ['Grand Vitara', 'Jimny', 'SX4', 'Swift', 'Vitara'],
    'Tank': ['300', '500'],
    'Tesla': ['Model 3', 'Model S', 'Model X', 'Model Y'],
    'Toyota': ['Alphard', 'Auris', 'Avalon', 'Avensis', 'Camry', 'Corolla', 'Fortuner', 'Highlander', 'Land Cruiser', 'Land Cruiser Prado', 'Prius', 'RAV4', 'Sequoia', 'Sienna', 'Tacoma', 'Tundra', 'Venza', 'Yaris'],
    'UAZ': ['Hunter', 'Patriot', 'Pickup'],
    'Volkswagen': ['Amarok', 'Arteon', 'Caddy', 'Golf', 'Jetta', 'Passat', 'Polo', 'Teramont', 'Tiguan', 'Touareg', 'Transporter'],
    'Volvo': ['S60', 'S80', 'S90', 'V60', 'XC40', 'XC60', 'XC70', 'XC90'],
    'Zeekr': ['001', '007', '009', 'X'],
};

async function main() {
    await db.carModel.deleteMany({});
    await db.carMake.deleteMany({});

    let makeId = 1;
    let modelId = 1;
    for (const [make, models] of Object.entries(catalog).sort(([a], [b]) => a.localeCompare(b))) {
        await db.carMake.create({
            data: { id: makeId, name: make },
        });
        for (const model of [...new Set(models)].sort((a, b) => a.localeCompare(b))) {
            await db.carModel.create({
                data: { id: modelId, makeId, name: model },
            });
            modelId += 1;
        }
        makeId += 1;
    }

    console.log(`Seeded clean car catalog: ${makeId - 1} makes, ${modelId - 1} models`);
}

main()
    .catch((error) => {
        console.error(error);
        process.exit(1);
    })
    .finally(async () => {
        await prisma.$disconnect();
    });
