# Mes Pictos

An iPad and iPhone app, inspired by PECS (Picture Exchange Communication System), that helps a
non-speaking or minimally-speaking autistic child communicate with pictograms spoken aloud in French.

The plan is in **[docs/PLAN.md](docs/PLAN.md)**. Step 1 of the roadmap is done, and the symbol library
of step 2 (ARASAAC search and the bundled starter kit) is in.

## What works in this version

- **Child mode.** Pages of large cards (1 to 4 by default). Tapping a card speaks it in French
  and brings it to the centre of the screen (**show mode**) so the child can show it to an adult.
  An adult closes it, and the card flies back to its place. Tapping the enlarged card speaks it again;
  swiping it in any direction throws it off the screen and closes it (unless closing is set to adult only).
- **Permanent bar** with three actions, visible on every page: "J'ai besoin d'aide", "Je veux", "Ouvre".
- **Sentence bar** (*bande phrase*). Tapping an action speaks it and slides a second bar up, just above the
  permanent bar. The child then taps one or more cards on the page (default 2) and they join the sentence.
  The big green **Dire** button brings the whole sentence to the centre of the screen and reads it as one
  sentence ("Je veux une pomme"), highlighting each card as it is spoken. Tapping it reads it again; swiping it in any direction
  throws the whole sentence off the screen and closes it, like a single card. Closing it clears the sentence.
  Tapping a card on the sentence bar takes it off again (the action clears the whole sentence).
  Tapping a card without an action first still shows and speaks that card alone. Action cards have a thick green border. Any card can be made an
  action ("Début de phrase") in its editor.
- **Parent mode**: press the lock for 3 seconds (optionally followed by a code, Face ID, or Touch ID).
  - Create, rename, reorder, and delete pages. Choose the grid size. Hide a page for the child (long-press its tab
    ▸ "Masquer pour l'enfant", or in the page settings): it keeps its cards and can be shown again in one tap.
  - Create a card from a photo (library or camera), crop it, set its label and spoken text, and record your voice.
  - Or pick a card from the **whole ARASAAC library** (about 13 000 pictograms with French keywords):
    "Chercher un pictogramme ARASAAC" in the card editor. The image is downloaded once and then works offline.
  - Move cards: drag onto another slot (cards swap), or onto a page tab. You can also long-press a card and use the
    menu: "Déplacer vers…", "Ajouter aussi sur…", "Masquer pour l'enfant", "Retirer de la page".
- **Starter kit** (*kit de démarrage*): 113 ARASAAC pictograms bundled with the app, offered at first launch and
  in the settings ("Ajouter le kit de démarrage"). The three actions go on the permanent bar, and there is one page
  per theme: Cartes critiques (non, oui, attends, fini, encore, pause), Débuts de phrase (je veux, je vois,
  j'entends, j'ai, c'est, je sens), Manger (18 foods and drinks), Jouer, Corps et soins, Personnes, Émotions,
  École, Animaux, Lieux et sorties. Adding the kit never touches existing pages or cards; it only marks existing
  "Je veux"-like cards as actions. The minimal option creates "Mes choses" (empty) and "Cartes critiques".
- **Settings**: French voice, speed and pitch, show mode (how it closes, auto-close, animation), label style
  (MAJUSCULES by default), sentence bar (on/off, words per sentence, clear after reading), ignoring repeated taps,
  parent mode protection, the starter kit, the ARASAAC credits, and two reset buttons (settings of this device,
  or erase everything and go back to the first launch).
- **iCloud sync** between the iPad and an iPhone signed in to the same iCloud account.

## Build and run on the iPad

Requirements: a Mac with **Xcode 16 or later**. The app targets iOS 18.0 and later.

1. **Open the project.**

   ```sh
   open mes-pictos.xcodeproj
   ```

2. **Check signing.** Select the `mes-pictos` target ▸ Signing & Capabilities. The project is set up with
   bundle identifier `lu.pata.mespictos` and automatic signing. If you use another Apple ID, change the team
   and the bundle identifier there. The iCloud container is `iCloud.<bundle identifier>`; Xcode creates it
   the first time you build for a device.

3. **Run on the iPad:**
   1. Connect the iPad with a cable.
   2. Select it as the run destination in Xcode and press ▶.
   3. The first time, on the iPad, trust the developer in Réglages ▸ Général ▸ VPN et gestion de l'appareil.
   4. On iPadOS 18, turn on Developer Mode in Réglages ▸ Confidentialité et sécurité.

4. **For the iPhone**, do the same. Both devices must use the same iCloud account for sync.

### Free Apple account (no paid developer membership)

iCloud sync needs the paid Apple Developer Program. With a free account:
- In Signing & Capabilities, remove the **iCloud** and **Push Notifications** capabilities (this empties
  `mes-pictos/mes-pictos.entitlements`). The app then stores its data on each device only.
- The app has to be re-installed from Xcode every 7 days.

## Tips for use with your child

- While Mes Pictos is in the foreground it keeps the speaker awake with a silent loop, so the first word after a
  pause is not clipped. Audio from other apps stops while Mes Pictos is open, as with any speaking app.

- Turn on **Accès guidé** (Réglages ▸ Accessibilité ▸ Accès guidé). Then triple-click the side or home button inside
  Mes Pictos, so your child cannot leave the app.
- Start with **photos of his real things and of the cards in his binder**, with few cards per page.
- Replace the action pictures with photos of the cards his speech therapist uses. Tap the card in parent mode, then "Choisir dans la photothèque" or "Prendre une photo".
- The kit's "Personnes" page is made of generic ARASAAC drawings: replace them with photos of the real people.
- Hide the kit pages he is not ready for (page settings ▸ "Masquer"), rather than deleting them.

## Project layout

```
mes-pictos.xcodeproj         Xcode project (app target + unit-test target, shared scheme "mes-pictos")
mes-pictos/
  App/                       app entry point
  Model/                     SwiftData models (CloudKit compatible) and PictoStore (all edits)
  Services/                  speech, voice recording, images, settings, device authentication
  Features/Board/            child mode, show mode, sentence bar and its overlay, page tabs, grid, drag and drop
  Features/Editor/           pictogram editor, crop, camera, page settings
  Features/SymbolSearch/     ARASAAC search sheet
  Resources/StarterKit/      StarterKit.json + one arasaac-<id>.png per pictogram (generated, see tools/)
  Features/Settings/         settings screen
  Features/Onboarding/       first launch
  Features/Lock/             parent lock and code
  Assets.xcassets            app icon and accent colour
  Info.plist                 usage descriptions, background modes (merged with the generated Info.plist)
  mes-pictos.entitlements    iCloud / CloudKit and push entitlements
mes-pictosTests/             store and starter kit tests (in-memory SwiftData)
Packages/PictoCore/          pure logic (grid moves and resize, speech priority, labels, crop math, ARASAAC API), with tests
tools/starter-kit/           build_kit.py: the kit vocabulary, resolves words to ARASAAC ids and downloads the images
```

The `mes-pictos/` and `mes-pictosTests/` folders are synchronized groups: Xcode picks up new files
automatically, so there is nothing to add to the project when you create a file. Resources in subfolders
(such as `Resources/StarterKit/`) end up at the root of the app bundle.

### Changing the starter kit

The vocabulary lives at the top of `tools/starter-kit/build_kit.py`: one line per card with the label, the
spoken text, the French word to search in ARASAAC, and optionally a pinned ARASAAC id. Then:

```sh
python3 tools/starter-kit/build_kit.py --check   # shows which pictogram each word resolves to
python3 tools/starter-kit/build_kit.py           # regenerates mes-pictos/Resources/StarterKit/
```

The tests check that every card of the kit has its image in the bundle.

## Tests

```sh
swift test --package-path Packages/PictoCore
xcodebuild test -project mes-pictos.xcodeproj -scheme mes-pictos -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro)'
```

GitHub Actions runs both on every push (`.github/workflows/ci.yml`).

An opt-in visual check renders the real board inside the test host, composes "Je veux" + "pomme", and saves
screenshots of the sentence bar and of the sentence shown in the centre:

```sh
TEST_RUNNER_SMOKE_SCREENSHOT_DIR=/tmp/shots xcodebuild test -project mes-pictos.xcodeproj -scheme mes-pictos \
  -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro)' -only-testing:mes-pictosTests/VisualSmokeTests
```

## Credits

Les symboles pictographiques utilisés sont la propriété du Gouvernement d'Aragon et ont été créés par Sergio Palao
pour [ARASAAC](https://arasaac.org), qui les distribue sous licence Creative Commons BY-NC-SA.

Because of the **NC** (non-commercial) and **SA** (share-alike) terms, the app cannot be sold, and anything that
contains these pictograms keeps the same licence. The attribution is shown in Réglages ▸ À propos et crédits and
under the ARASAAC search. Each pictogram records its source (`source`, `sourceRef`, `licence`), so exports can carry it.
