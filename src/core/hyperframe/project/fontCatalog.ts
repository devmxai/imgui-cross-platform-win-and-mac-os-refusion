export type ProfessionalFontCategory =
  | "caption"
  | "modern-sans"
  | "editorial-serif"
  | "display-title"
  | "condensed"
  | "rounded"
  | "mono-tech"
  | "script-hand"
  | "retro-vintage"
  | "luxury-fashion";

export type ProfessionalFont = {
  family: string;
  source: "google" | "fontshare";
  sourceSlug?: string;
  license: "OFL/Apache via Google Fonts" | "Fontshare free commercial license";
  category: ProfessionalFontCategory;
  tags: string[];
  weights: number[];
  recommended: boolean;
};

const fontGroups: Record<ProfessionalFontCategory, string[]> = {
  caption: [
    "Inter", "Roboto", "Open Sans", "Lato", "Montserrat", "Poppins", "DM Sans", "Manrope",
    "Plus Jakarta Sans", "Nunito Sans", "Source Sans 3", "Work Sans", "Public Sans", "Figtree",
    "Instrument Sans", "Atkinson Hyperlegible", "Lexend", "Barlow", "Archivo", "Noto Sans",
    "Hind", "Assistant", "Karla", "Mulish", "Rubik", "Quicksand", "IBM Plex Sans",
    "PT Sans", "Arimo", "Cabin", "Overpass", "Red Hat Display", "Red Hat Text",
  ],
  "modern-sans": [
    "Outfit", "Urbanist", "Sora", "Space Grotesk", "Syne", "Epilogue", "Exo 2", "Chakra Petch",
    "Jost", "Raleway", "Afacad", "Onest", "Albert Sans", "Geologica", "Gabarito", "REM",
    "Ysabeau", "Ysabeau Office", "Alegreya Sans", "Asap", "Asap Condensed", "Barlow Semi Condensed",
    "Titillium Web", "Maven Pro", "Varela Round", "Questrial", "Hanken Grotesk", "Schibsted Grotesk",
    "Wix Madefor Display", "Wix Madefor Text", "Noto Sans Display", "Noto Sans Symbols",
  ],
  "editorial-serif": [
    "Playfair Display", "Cormorant Garamond", "Cormorant", "Libre Baskerville", "Lora", "Merriweather",
    "Crimson Pro", "Crimson Text", "EB Garamond", "Bodoni Moda", "Prata", "DM Serif Display",
    "DM Serif Text", "Fraunces", "Instrument Serif", "Newsreader", "Spectral", "Vollkorn",
    "Alegreya", "Cardo", "Tinos", "Libre Caslon Text", "Libre Caslon Display", "Cormorant Infant",
    "Cormorant SC", "Cormorant Unicase", "Gloock", "Baskervville", "Baskervville SC", "Literata",
    "Source Serif 4", "Noto Serif", "Noto Serif Display", "PT Serif", "Brygada 1918", "STIX Two Text",
  ],
  "display-title": [
    "Anton", "Archivo Black", "Bebas Neue", "Bangers", "Black Ops One", "Bowlby One SC", "Bungee",
    "Bungee Inline", "Bungee Shade", "Erica One", "Fascinate Inline", "Fugaz One", "Graduate",
    "Gravitas One", "Holtwood One SC", "Limelight", "Monoton", "Notable", "Passion One",
    "Patua One", "Paytone One", "Racing Sans One", "Rammetto One", "Righteous", "Rowdies",
    "Rubik Mono One", "Russo One", "Secular One", "Sigmar", "Spicy Rice", "Staatliches",
    "Titan One", "Ultra", "Unica One", "Yeseva One", "Chango", "Concert One", "Lilita One",
    "Luckiest Guy", "Modak", "Oi", "Sonsie One", "Wendy One", "Zen Tokyo Zoo",
  ],
  condensed: [
    "Oswald", "Roboto Condensed", "Archivo Narrow", "Barlow Condensed", "IBM Plex Sans Condensed",
    "Encode Sans Condensed", "Yanone Kaffeesatz", "Teko", "Fjalla One", "League Gothic",
    "League Spartan", "Saira Condensed", "Saira Semi Condensed", "Saira Extra Condensed",
    "Alegreya Sans SC", "Open Sans Condensed", "Pathway Gothic One", "Rajdhani", "Tauri",
    "Gemunu Libre", "Big Shoulders Display", "Big Shoulders Text", "Six Caps", "Stint Ultra Condensed",
  ],
  rounded: [
    "Nunito", "Baloo 2", "Baloo Bhai 2", "Baloo Chettan 2", "Baloo Da 2", "Baloo Paaji 2",
    "Fredoka", "Comfortaa", "Quicksand", "M PLUS Rounded 1c", "Varela Round", "Dosis",
    "Exo", "Kanit", "Ubuntu", "Mitr", "Sniglet", "Sofia Sans", "Sofia Sans Semi Condensed",
    "Sofia Sans Condensed", "Sofia Sans Extra Condensed", "Nunito Sans",
  ],
  "mono-tech": [
    "Roboto Mono", "JetBrains Mono", "Source Code Pro", "IBM Plex Mono", "Space Mono", "Fira Code",
    "Fira Mono", "Inconsolata", "DM Mono", "Azeret Mono", "Anonymous Pro", "Cousine",
    "Cutive Mono", "Share Tech Mono", "Major Mono Display", "Red Hat Mono", "Noto Sans Mono",
    "Kode Mono", "Fragment Mono", "Spline Sans Mono", "Ubuntu Mono",
  ],
  "script-hand": [
    "Pacifico", "Lobster", "Lobster Two", "Dancing Script", "Caveat", "Satisfy", "Great Vibes",
    "Allura", "Alex Brush", "Sacramento", "Yellowtail", "Kaushan Script", "Kalam", "Patrick Hand",
    "Indie Flower", "Shadows Into Light", "Shadows Into Light Two", "Architects Daughter",
    "Amatic SC", "Gloria Hallelujah", "Courgette", "Merienda", "Norican", "Parisienne",
    "Petit Formal Script", "Rochester", "Rouge Script", "Yesteryear", "Handlee", "Coming Soon",
    "Covered By Your Grace", "Homemade Apple", "Just Another Hand", "Rock Salt", "Schoolbell",
  ],
  "retro-vintage": [
    "Abril Fatface", "Alfa Slab One", "Arvo", "BioRhyme", "Bree Serif", "Eczar", "Grenze",
    "Knewave", "Londrina Solid", "Londrina Outline", "Londrina Shadow", "Londrina Sketch",
    "Miltonian", "Miltonian Tattoo", "Rye", "Sancreek", "Smokum", "Special Elite",
    "Vast Shadow", "Wallpoet", "Diplomata", "Diplomata SC", "Ewert", "Faster One",
    "Fredericka the Great", "Fontdiner Swanky", "Goblin One", "Mystery Quest", "Ribeye",
    "Ribeye Marrow", "Risque", "Rye", "Trade Winds",
  ],
  "luxury-fashion": [
    "Cinzel", "Cinzel Decorative", "Marcellus", "Marcellus SC", "Oranienbaum", "Suranna",
    "Trirong", "Rosarivo", "Italiana", "Italianno", "Julius Sans One", "Forum",
    "Bellefair", "Belleza", "Cormorant Upright", "Caudex", "Elsie",
    "Elsie Swash Caps", "Mate", "Mate SC", "Sorts Mill Goudy", "Tenor Sans",
    "Viaoda Libre", "Vidaloka", "Fanwood Text", "Gilda Display", "Judson",
  ],
};

const categoryTags: Record<ProfessionalFontCategory, string[]> = {
  caption: ["caption", "subtitle", "reels", "readable", "ui"],
  "modern-sans": ["modern", "startup", "clean", "brand", "social"],
  "editorial-serif": ["editorial", "serif", "magazine", "luxury", "title"],
  "display-title": ["bold", "title", "poster", "thumbnail", "impact"],
  condensed: ["condensed", "sports", "fashion", "vertical", "headline"],
  rounded: ["friendly", "rounded", "creator", "soft", "caption"],
  "mono-tech": ["tech", "code", "terminal", "sci-fi", "data"],
  "script-hand": ["script", "handwritten", "signature", "organic", "creator"],
  "retro-vintage": ["retro", "vintage", "poster", "character", "nostalgia"],
  "luxury-fashion": ["luxury", "fashion", "elegant", "high-contrast", "brand"],
};

const recommendedFamilies = new Set([
  "Inter", "Montserrat", "Poppins", "DM Sans", "Manrope", "Plus Jakarta Sans", "Instrument Sans",
  "Playfair Display", "Cormorant Garamond", "Bodoni Moda", "Fraunces", "Gloock", "Anton",
  "Bebas Neue", "Archivo Black", "Oswald", "Roboto Condensed", "League Spartan", "Pacifico",
  "Caveat", "Dancing Script", "Abril Fatface", "Cinzel", "Space Grotesk", "Syne",
]);

const defaultWeights = [100, 200, 300, 400, 500, 600, 700, 800, 900];

const createFontCollection = () => {
  const seen = new Set<string>();
  const googleFonts = Object.entries(fontGroups).flatMap(([category, families]) => families.flatMap((family) => {
    if (seen.has(family)) return [];
    seen.add(family);
    return [{
      family,
      source: "google" as const,
      license: "OFL/Apache via Google Fonts" as const,
      category: category as ProfessionalFontCategory,
      tags: categoryTags[category as ProfessionalFontCategory],
      weights: defaultWeights,
      recommended: recommendedFamilies.has(family),
    }];
  }));
  const fontshareFonts: Array<Pick<ProfessionalFont, "family" | "sourceSlug" | "category" | "tags" | "recommended">> = [
    { family: "Satoshi", sourceSlug: "satoshi", category: "modern-sans", tags: ["modern", "brand", "caption", "social"], recommended: true },
    { family: "Clash Display", sourceSlug: "clash-display", category: "display-title", tags: ["display", "title", "poster", "bold"], recommended: true },
    { family: "Clash Grotesk", sourceSlug: "clash-grotesk", category: "modern-sans", tags: ["modern", "grotesk", "brand"], recommended: true },
    { family: "General Sans", sourceSlug: "general-sans", category: "modern-sans", tags: ["clean", "brand", "caption"], recommended: true },
    { family: "Cabinet Grotesk", sourceSlug: "cabinet-grotesk", category: "display-title", tags: ["display", "rounded", "poster"], recommended: true },
    { family: "Switzer", sourceSlug: "switzer", category: "caption", tags: ["caption", "ui", "clean"], recommended: true },
    { family: "Sentient", sourceSlug: "sentient", category: "editorial-serif", tags: ["editorial", "serif", "luxury"], recommended: true },
    { family: "Boska", sourceSlug: "boska", category: "luxury-fashion", tags: ["fashion", "serif", "editorial"], recommended: true },
    { family: "Zodiak", sourceSlug: "zodiak", category: "luxury-fashion", tags: ["luxury", "serif", "fashion"], recommended: true },
    { family: "Gambetta", sourceSlug: "gambetta", category: "editorial-serif", tags: ["editorial", "serif", "italic"], recommended: false },
    { family: "Tanker", sourceSlug: "tanker", category: "display-title", tags: ["bold", "poster", "thumbnail"], recommended: true },
    { family: "Panchang", sourceSlug: "panchang", category: "display-title", tags: ["wide", "tech", "poster"], recommended: false },
    { family: "Chillax", sourceSlug: "chillax", category: "rounded", tags: ["rounded", "modern", "creator"], recommended: false },
    { family: "Supreme", sourceSlug: "supreme", category: "caption", tags: ["caption", "ui", "modern"], recommended: false },
    { family: "Melodrama", sourceSlug: "melodrama", category: "luxury-fashion", tags: ["display", "fashion", "serif"], recommended: false },
    { family: "Telma", sourceSlug: "telma", category: "script-hand", tags: ["script", "expressive", "title"], recommended: false },
  ];
  return [
    ...googleFonts,
    ...fontshareFonts.map((font) => ({
      ...font,
      source: "fontshare" as const,
      license: "Fontshare free commercial license" as const,
      weights: defaultWeights,
    })),
  ];
};

export const PROFESSIONAL_FONT_COLLECTION: ProfessionalFont[] = createFontCollection();

export const PROFESSIONAL_FONT_CATEGORIES = Object.keys(fontGroups) as ProfessionalFontCategory[];

export const getProfessionalFont = (family?: string) =>
  PROFESSIONAL_FONT_COLLECTION.find((font) => font.family === family) ?? PROFESSIONAL_FONT_COLLECTION[0];

const encodeGoogleFamily = (family: string) => family.trim().replace(/\s+/g, "+");

export const createGoogleFontStylesheetUrl = (families: string[]) => {
  const googleFamilySet = new Set(PROFESSIONAL_FONT_COLLECTION.filter((font) => font.source === "google").map((font) => font.family));
  const uniqueFamilies = Array.from(new Set(families.map((family) => family.trim()).filter((family) => googleFamilySet.has(family))));
  if (uniqueFamilies.length === 0) return "";
  const familyQuery = uniqueFamilies
    .map((family) => `family=${encodeGoogleFamily(family)}`)
    .join("&");
  return `https://fonts.googleapis.com/css2?${familyQuery}&display=swap`;
};

export const createFontshareStylesheetUrl = (families: string[]) => {
  const requested = new Set(families.map((family) => family.trim()).filter(Boolean));
  const fontshareFonts = PROFESSIONAL_FONT_COLLECTION
    .filter((font) => font.source === "fontshare" && requested.has(font.family) && font.sourceSlug)
    .map((font) => font.sourceSlug);
  const uniqueSlugs = Array.from(new Set(fontshareFonts));
  if (uniqueSlugs.length === 0) return "";
  const familyQuery = uniqueSlugs.map((slug) => `f[]=${slug}@300,400,500,600,700,800,900`).join("&");
  return `https://api.fontshare.com/v2/css?${familyQuery}&display=swap`;
};

export const createFontStylesheetUrls = (families: string[]) =>
  [createGoogleFontStylesheetUrl(families), createFontshareStylesheetUrl(families)].filter(Boolean);

export const createFontCatalogForWorkspace = () => ({
  version: 1,
  updatedAt: "2026-05-18",
  sourcePolicy: "Only verified free-commercial/open font sources are included: Google Fonts and Fontshare. Commercial/private fonts should be added by the user with their own license.",
  runtime: {
    defaultFamily: "Inter",
    dynamicLoading: "Google Fonts families are loaded on demand by the app and preview renderer.",
    agentUsage: "Set timeline text clips with text.fontFamily, text.fontWeight, text.fontStyle, text.fontSize, and text.color.",
  },
  fonts: PROFESSIONAL_FONT_COLLECTION,
});
