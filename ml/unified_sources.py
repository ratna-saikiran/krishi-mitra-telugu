"""Label map for the unified crop + disease + pest classifier.
Unified label = "<Crop>___<condition>". None = drop that source class
(fruit-only photos, ambiguous or non-Indian classes). Hugging Face sources are
Project-AgML mirrors of published datasets; see docs/technical_report.md."""

HF = {
 # Rice
 "Project-AgML/paddy_disease_classification": {
  "bacterial_leaf_blight": "Rice___Bacterial_leaf_blight", "bacterial_leaf_streak": "Rice___Bacterial_leaf_streak",
  "bacterial_panicle_blight": "Rice___Bacterial_panicle_blight", "blast": "Rice___Blast", "brown_spot": "Rice___Brown_spot",
  "dead_heart": "Rice___Stem_borer_dead_heart", "downy_mildew": "Rice___Downy_mildew", "hispa": "Rice___Hispa",
  "normal": "Rice___healthy", "tungro": "Rice___Tungro"},
 "Project-AgML/rice_leaf_disease_classification": {
  "Bacterial_Leaf_Blight": "Rice___Bacterial_leaf_blight", "Brown_Spot": "Rice___Brown_spot", "Healthy_Rice_Leaf": "Rice___healthy",
  "Leaf_Blast": "Rice___Blast", "Leaf_Scald": "Rice___Leaf_scald", "Sheath_Blight": "Rice___Sheath_blight"},
 # Cotton
 "Project-AgML/cotton_leaf_disease_classification": {
  "Alternaria_Leaf": "Cotton___Alternaria_leaf_spot", "Bacterial_Blight": "Cotton___Bacterial_blight",
  "Fusarium_Wilt": "Cotton___Fusarium_wilt", "Healthy_Leaf": "Cotton___healthy", "Verticillium_Wilt": "Cotton___Verticillium_wilt"},
 "Project-AgML/cotton_leaf_disease_classification_bangladesh_2": {
  "Bacterial Blight": "Cotton___Bacterial_blight", "Curl Virus": "Cotton___Leaf_curl_virus", "Healthy Leaf": "Cotton___healthy",
  "Herbicide Growth Damage": None, "Leaf Hopper Jassids": "Cotton___Jassids", "Leaf Redding": "Cotton___Leaf_reddening",
  "Leaf Variegation": None},
 # Chilli
 "Project-AgML/COLD_chili_leaf_disease_classification": {
  "cercospora": "Chilli___Cercospora_leaf_spot", "healthy": "Chilli___healthy", "mites_and_trips": "Chilli___Mites_and_thrips",
  "nutritional": "Chilli___Nutrient_deficiency", "powdery mildew": "Chilli___Powdery_mildew"},
 # Groundnut
 "Project-AgML/groundnut_leaf_disease_classification": {
  "ALTERNARIA LEAF SPOT": "Groundnut___Alternaria_leaf_spot", "HEALTHY": "Groundnut___healthy", "LEAF SPOT": "Groundnut___Tikka_leaf_spot",
  "ROSETTE": "Groundnut___Rosette", "RUST": "Groundnut___Rust"},
 "Project-AgML/groundnut_leaf_disease_classification_2": {
  "early_leaf_spot": "Groundnut___Tikka_leaf_spot", "healthy leaf": "Groundnut___healthy", "late leaf spot": "Groundnut___Tikka_leaf_spot",
  "nutrition deficiency": "Groundnut___Nutrient_deficiency", "rust": "Groundnut___Rust"},
 # Black gram
 "Project-AgML/blackgram_plant_leaf_disease_classification": {
  "anthracnose": "Blackgram___Anthracnose", "healthy": "Blackgram___healthy", "leaf_crinckle": "Blackgram___Leaf_crinkle",
  "powdery_mildew": "Blackgram___Powdery_mildew", "yellow_mosaic": "Blackgram___Yellow_mosaic"},
 # Vegetables
 "Project-AgML/eggplant_leaf_disease_classification": {
  "Aphids": "Brinjal___Aphids", "Cercospora Leaf Spot": "Brinjal___Cercospora_leaf_spot", "Defect Eggplant": None,
  "Flea Beetles": "Brinjal___Flea_beetles", "Fresh Eggplant": None, "Fresh Eggplant Leaf": "Brinjal___healthy",
  "Leaf Wilt": "Brinjal___Wilt", "Phytophthora Blight": "Brinjal___Phytophthora_blight", "Powdery Mildew": "Brinjal___Powdery_mildew",
  "Tobacco Mosaic Virus": "Brinjal___Mosaic_virus"},
 "Project-AgML/OkraDiseaseNet_disease_classification": {
  "Alternaria Leaf Spot": "Okra___Alternaria_leaf_spot", "Cercospora Leaf Spot": "Okra___Cercospora_leaf_spot",
  "Downy Mildew": "Okra___Downy_mildew", "Healthy": "Okra___healthy", "Leaf curly virus": "Okra___Leaf_curl_virus",
  "Phyllosticta leaf spot": "Okra___Phyllosticta_leaf_spot"},
 "Project-AgML/ash_gourd_disease_classification": {
  "Aphid": "Gourd___Aphids", "Downy mildew": "Gourd___Downy_mildew", "Healthy": "Gourd___healthy",
  "Leaf curl": "Gourd___Leaf_curl_virus", "Leaf miner": "Gourd___Leaf_miner"},
 "Project-AgML/cucumber_disease_classification": {
  "Anthracnose": "Cucumber___Anthracnose", "Bacterial_Wilt": "Cucumber___Bacterial_wilt", "Belly_Rot": None,
  "Downy_Mildew": "Cucumber___Downy_mildew", "Fresh_Cucumber": None, "Fresh_Leaf": "Cucumber___healthy",
  "Gummy_Stem_Blight": "Cucumber___Gummy_stem_blight", "Pythium_Fruit_Rot": None},
 "Project-AgML/watermelon_disease_classification": {
  "Anthracnose": "Watermelon___Anthracnose", "Downy_Mildew": "Watermelon___Downy_mildew", "Healthy": "Watermelon___healthy",
  "Mosaic_Virus": "Watermelon___Mosaic_virus"},
 # Fruit / plantation
 "Project-AgML/mango_leaf_disease_classification": {
  "Anthracnose": "Mango___Anthracnose", "Bacterial_Canker": "Mango___Bacterial_canker", "Cutting_Weevil": "Mango___Cutting_weevil",
  "Die_Back": "Mango___Die_back", "Gall_Midge": "Mango___Gall_midge", "Healthy": "Mango___healthy",
  "Powdery_Mildew": "Mango___Powdery_mildew", "Sooty_Mold": "Mango___Sooty_mould"},
 "Project-AgML/banana_leaf_disease_classification": {
  "healthy": "Banana___healthy", "segatoka": "Banana___Sigatoka", "xamthomonas": "Banana___Xanthomonas_wilt"},
 "Project-AgML/papaya_leaf_disease_classification_bangladesh": {
  "Healthy Leaf": "Papaya___healthy", "Leaf Curl": "Papaya___Leaf_curl_virus", "Mealybug": "Papaya___Mealybug",
  "Mite Disease": "Papaya___Mites", "Mosaic": "Papaya___Mosaic_virus", "Ring Spot": "Papaya___Ring_spot_virus"},
 "Project-AgML/orange_leaf_disease_classification": {
  "citrus_canker": "Orange___Citrus_canker", "citrus_greening": "Orange___Haunglongbing_(Citrus_greening)",
  "citrus_mealybugs": "Orange___Mealybugs", "die_back": "Orange___Die_back", "foliage_damaged": None,
  "healthy_leaf": "Orange___healthy", "powdery_mildew": "Orange___Powdery_mildew", "shot_hole": None,
  "spiny_whitefly": "Orange___Spiny_whitefly", "yellow_dragon": "Orange___Haunglongbing_(Citrus_greening)", "yellow_leaves": None},
 "Project-AgML/sugarcane_leaf_disease_classification": {
  "Banded Chlorosis": "Sugarcane___Banded_chlorosis", "Brown Spot": "Sugarcane___Brown_spot", "BrownRust": "Sugarcane___Rust",
  "Dried": None, "Grassy shoot": "Sugarcane___Grassy_shoot", "Healthy": "Sugarcane___healthy", "Pokkah Boeng": "Sugarcane___Pokkah_boeng",
  "Sett Rot": None, "Smut": "Sugarcane___Smut", "Viral Disease": "Sugarcane___Mosaic_virus", "Yellow Leaf": "Sugarcane___Yellow_leaf"},
 "Project-AgML/turmeric_leaf_disease_classification": {
  "Aphids_Disease": "Turmeric___Aphids", "Blotch": "Turmeric___Leaf_blotch", "Healthy_Leaf": "Turmeric___healthy",
  "Leaf_Spot": "Turmeric___Leaf_spot"},
 # Field-condition healthy maize (East African MLN/MSV classes dropped)
 "Project-AgML/maize_disease_classification": {"Healthy": "Corn_(maize)___healthy", "MLN": None, "MSV": None},
}
IP102 = "EnmmmmOvO/insect-pest-dataset"   # IP102 (45,095 / 7,508 / 22,619 official splits)
