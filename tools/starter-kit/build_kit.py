#!/usr/bin/env python3
"""Builds the starter kit (kit de démarrage) bundled with the app.

For each word below, the script asks the ARASAAC API for the best French match (or uses the
pinned id), downloads the 500 px PNG and writes
  mes-pictos/Resources/StarterKit/StarterKit.json
  mes-pictos/Resources/StarterKit/arasaac-<id>.png

Usage, from the repository root:
  python3 tools/starter-kit/build_kit.py          # rebuild everything
  python3 tools/starter-kit/build_kit.py --check  # only print the resolved ids, download nothing

To change a pictogram, put its ARASAAC id as the 4th element of the item. Browse ids on
https://arasaac.org. The pictograms are CC BY-NC-SA, Government of Aragon, drawings by Sergio Palao.
Standard library only, no dependencies.
"""
import json, os, shutil, sys, time, urllib.parse, urllib.request


# Cards that open the sentence bar (bande phrase) instead of being shown alone.
STARTERS = {"Aide", "Je veux", "Ouvre", "Je vois", "J'entends", "J'ai", "C'est", "Je sens"}

BAR = ("Barre permanente", 3, 1, [
    ("Aide", "J'ai besoin d'aide", "aide", 12252),
    ("Je veux", None, "je veux", 5441),
    ("Ouvre", None, "ouvrir", 6875),
])

PAGES = [
    ("Cartes critiques", 3, 2, [
        ("Non", None, "non", 5526),
        ("Oui", None, "oui", 5584),
        ("Attends", None, "attendre", 16697),
        ("Fini", "C'est fini", "fini", 5358),
        ("Encore", None, "encore", 32753),
        ("Pause", "Je veux une pause", "pause", 38213),
    ]),
    ("Débuts de phrase", 3, 2, [
        ("Je veux", None, "je veux", None),
        ("Je vois", None, "je vois", None),
        ("J'entends", None, "entendre", None),
        ("J'ai", None, "j'ai", 7271),
        ("C'est", None, "c'est", 5466),
        ("Je sens", None, "sentir", 2486),
    ]),
    ("Manger", 6, 3, [
        ("pomme", "une pomme", "pomme", None),
        ("banane", "une banane", "banane", None),
        ("fraise", "une fraise", "fraise", None),
        ("compote", "une compote", "compote", None),
        ("pain", "du pain", "pain", None),
        ("fromage", "du fromage", "fromage", None),
        ("yaourt", "un yaourt", "yaourt", None),
        ("gâteau", "un gâteau", "gâteau", None),
        ("biscuit", "un biscuit", "biscuit", None),
        ("chocolat", "du chocolat", "chocolat", None),
        ("pâtes", "des pâtes", "pâtes", None),
        ("riz", "du riz", "riz", 39387),
        ("poulet", "du poulet", "poulet", 24815),
        ("frites", "des frites", "frites", None),
        ("pizza", "une pizza", "pizza", None),
        ("eau", "de l'eau", "eau", 2248),
        ("lait", "du lait", "lait", None),
        ("jus", "du jus d'orange", "jus d'orange", None),
    ]),
    ("Jouer", 4, 3, [
        ("ballon", "un ballon", "ballon", 2269),
        ("voiture", "une petite voiture", "petite voiture", None),
        ("poupée", "une poupée", "poupée", None),
        ("puzzle", "un puzzle", "puzzle", None),
        ("cubes", "des cubes", "cubes", None),
        ("livre", "un livre", "livre", None),
        ("tablette", "la tablette", "tablette", None),
        ("télé", "la télé", "télévision", None),
        ("musique", "de la musique", "musique", None),
        ("dessiner", None, "dessiner", None),
        ("bulles", "des bulles", "bulles de savon", None),
        ("toboggan", "le toboggan", "toboggan", None),
    ]),
    ("Corps et soins", 4, 3, [
        ("toilettes", "les toilettes", "toilettes", None),
        ("dormir", None, "dormir", None),
        ("mal", "J'ai mal", "avoir mal", None),
        ("laver les mains", "me laver les mains", "se laver les mains", None),
        ("bain", "le bain", "bain", 6058),
        ("brosser les dents", "me brosser les dents", "se brosser les dents", None),
        ("s'habiller", None, "s'habiller", None),
        ("chaussures", "les chaussures", "chaussures", None),
        ("manteau", "le manteau", "manteau", None),
        ("médicament", "un médicament", "médicament", None),
        ("mouchoir", "un mouchoir", "mouchoir", None),
        ("boire", None, "boire", None),
    ]),
    ("Personnes", 4, 3, [
        ("maman", None, "maman", None),
        ("papa", None, "papa", None),
        ("frère", "mon frère", "frère", None),
        ("sœur", "ma sœur", "sœur", None),
        ("mamie", None, "grand-mère", None),
        ("papi", None, "grand-père", None),
        ("bébé", "le bébé", "bébé", None),
        ("copain", "un copain", "ami", None),
        ("maîtresse", "la maîtresse", "maîtresse", None),
        ("orthophoniste", "l'orthophoniste", "orthophoniste", None),
        ("docteur", "le docteur", "médecin", None),
        ("moi", None, "moi", None),
    ]),
    ("Émotions", 4, 2, [
        ("content", "Je suis content", "content", None),
        ("triste", "Je suis triste", "triste", None),
        ("fâché", "Je suis fâché", "en colère", None),
        ("peur", "J'ai peur", "avoir peur", 35571),
        ("fatigué", "Je suis fatigué", "fatigué", None),
        ("malade", "Je suis malade", "malade", None),
        ("calme", "Je suis calme", "calme", None),
        ("surpris", "Je suis surpris", "surpris", None),
    ]),
    ("École", 4, 3, [
        ("école", "l'école", "école", None),
        ("cartable", "le cartable", "cartable", 2475),
        ("crayon", "un crayon", "crayon", None),
        ("ciseaux", "les ciseaux", "ciseaux", None),
        ("colle", "la colle", "colle", None),
        ("cahier", "le cahier", "cahier", None),
        ("peinture", "la peinture", "peinture", 4950),
        ("pâte à modeler", "la pâte à modeler", "pâte à modeler", None),
        ("récréation", "la récréation", "récréation", None),
        ("cantine", "la cantine", "cantine", None),
        ("bus", "le bus", "autobus", None),
        ("s'asseoir", None, "s'asseoir", None),
    ]),
    ("Animaux", 4, 3, [
        ("chien", "un chien", "chien", None),
        ("chat", "un chat", "chat", None),
        ("lapin", "un lapin", "lapin", None),
        ("oiseau", "un oiseau", "oiseau", None),
        ("poisson", "un poisson", "poisson", None),
        ("cheval", "un cheval", "cheval", None),
        ("vache", "une vache", "vache", None),
        ("cochon", "un cochon", "cochon", None),
        ("mouton", "un mouton", "mouton", None),
        ("poule", "une poule", "poule", None),
        ("canard", "un canard", "canard", None),
        ("éléphant", "un éléphant", "éléphant", None),
    ]),
    ("Lieux et sorties", 4, 3, [
        ("maison", "la maison", "maison", None),
        ("parc", "le parc", "parc", 2434),
        ("aire de jeux", "l'aire de jeux", "aire de jeux", None),
        ("piscine", "la piscine", "piscine", None),
        ("supermarché", "le supermarché", "supermarché", None),
        ("boulangerie", "la boulangerie", "boulangerie", None),
        ("plage", "la plage", "plage", None),
        ("forêt", "la forêt", "forêt", None),
        ("restaurant", "le restaurant", "restaurant", None),
        ("bibliothèque", "la bibliothèque", "bibliothèque", None),
        ("promenade", "une promenade", "se promener", None),
        ("voiture", "la voiture", "voiture", None),
    ]),
]


ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEST = os.path.join(ROOT, "mes-pictos", "Resources", "StarterKit")
API = "https://api.arasaac.org/v1/pictograms/fr/"
CHECK_ONLY = "--check" in sys.argv


def get_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": "mes-pictos-kit/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return []
        raise


def resolve(term):
    """Best ARASAAC match: exact keyword first, then the AAC-flagged, then non-schematic drawings."""
    results = get_json(API + "bestsearch/" + urllib.parse.quote(term)) or get_json(API + "search/" + urllib.parse.quote(term))
    time.sleep(0.2)

    def score(p):
        keywords = [k.get("keyword", "").lower() for k in p.get("keywords", [])]
        return (p.get("sex") or p.get("violence"), term.lower() not in keywords, not p.get("aacColor"), not p.get("aac"), p.get("schematic", False))

    ranked = sorted(results, key=score)
    return ranked[0]["_id"] if ranked else None


def download(pid):
    path = os.path.join(DEST, f"arasaac-{pid}.png")
    if os.path.exists(path):
        return
    url = f"https://static.arasaac.org/pictograms/{pid}/{pid}_500.png"
    request = urllib.request.Request(url, headers={"User-Agent": "mes-pictos-kit/1.0"})
    with urllib.request.urlopen(request, timeout=30) as response:
        open(path, "wb").write(response.read())
    time.sleep(0.1)


def build_page(title, columns, rows, items):
    assert len(items) <= columns * rows, f"{title}: {len(items)} items for {columns * rows} slots"
    out = []
    for label, spoken, term, forced in items:
        pid = forced or resolve(term)
        if pid is None:
            sys.exit(f"No ARASAAC pictogram found for '{term}' ({title} / {label}). Pin an id in the list.")
        print(f"{title:18} {label:20} {term:22} -> {pid}{'  (pinned)' if forced else ''}")
        item = {"label": label, "arasaac": pid}
        if spoken:
            item["spoken"] = spoken
        if label in STARTERS:
            item["starter"] = True
        out.append(item)
    return {"title": title, "columns": columns, "rows": rows, "items": out}


def main():
    kit = {
        "version": 2,
        "source": "ARASAAC",
        "licence": "CC BY-NC-SA – ARASAAC",
        "bar": build_page(*BAR),
        "pages": [build_page(*page) for page in PAGES],
    }
    if CHECK_ONLY:
        return
    if os.path.isdir(DEST):
        shutil.rmtree(DEST)
    os.makedirs(DEST)
    ids = {item["arasaac"] for page in [kit["bar"]] + kit["pages"] for item in page["items"]}
    for pid in sorted(ids):
        download(pid)
    with open(os.path.join(DEST, "StarterKit.json"), "w") as f:
        json.dump(kit, f, ensure_ascii=False, indent=1)
    total = sum(len(page["items"]) for page in [kit["bar"]] + kit["pages"])
    print(f"{total} pictograms, {len(ids)} images written to {DEST}")


if __name__ == "__main__":
    main()
