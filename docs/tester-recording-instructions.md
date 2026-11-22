# App Review video recording — MacroMeister (iPhone) — full instructions

> For the app-review screen recording Apple requested. Forward this file to the
> tester. The AI provider details (base URL, API key, model name) are sent
> separately and privately by the app owner.

## Setup (one time, before recording)

1. Use a physical iPhone running the **latest iOS** (Settings → General →
   Software Update — must be current)
2. Install the app from **TestFlight** (an invite arrives by email — open it on
   the phone and accept)
3. Turn on **Do Not Disturb** so no banners/messages appear in the recording
4. Add screen recording to Control Center: Settings → Control Center → add
   "Screen Recording"
5. Have a packaged product with a barcode at hand (any snack box)

## AI provider details (important)

The app owner will provide you **all three AI provider details privately**
(Signal/email, not publicly):

- the **API base URL** (if the provider is not the default),
- the **API key**,
- and the **model name** to select in the app.

You will enter these on the phone now, and again on camera during the
recording. The key field is masked and will not be visible anywhere in the
recording.

## Configure the AI provider (on the phone, before recording — ~1 min)

Open **MacroMeister → More → AI settings**: enter the provided **base URL**
(if given), paste the **API key**, and enter the provided **model name**
exactly as written. Tap **Test connection** and confirm it succeeds, then
Save. You will repeat this on camera during the recording (see below).

## Recording (portrait, one continuous take, ~5 minutes)

1. Start the screen recording **from the home screen** (Control Center →
   long-press the record button → Start). The recording must begin *before*
   opening the app — Apple wants to see the launch itself
2. Open **MacroMeister** from the home screen and let it load

### Walk through this flow in order, pausing 1–2 seconds on each screen

**Onboarding**

- Complete the setup wizard: About you (pick sex, enter birth year), Your body
  (height/weight), Your goal (set a goal weight and drag the weekly-rate
  slider), Activity level, check-in day → **Create program**

**AI provider setup (on camera)**

- More → AI settings → enter the provided base URL (if given) → paste the API
  key (masked — not visible in the recording) → enter the model name → tap
  **Test connection** → let the success confirmation show → Save

**Dashboard**

- Show the calorie ring, macro bars, water card
- Log a glass of water (+250 ml), then undo it

**Add food — every input method**

- Tap **+** → **Quick add**: enter calories/macros, save
- **Search**: search a food, select it, save
- **Barcode scan**: point the camera at the packaged product, let it read the
  barcode, save
- **"AI describe"**: type "chicken rice bowl with olive oil", let the macro
  estimate appear, then edit one value to show it is adjustable

**Log screen**

- Open a day, show the meal sections
- Tap an entry to edit it; swipe one away to delete it
- Use "Copy yesterday's meals" if yesterday has entries

**Program**

- Open the Program tab, tap **Edit program**, drag the weekly-rate slider up
  and down (the label "Losing/Gaining X kg/week" follows), save
- Do the weekly check-in: enter a weight, save

**More tab**

- Open **Data sources & licenses** (shows the Open Food Facts / USDA
  attributions)
- Show **Settings → Reminders**, toggle the daily reminder on — let the
  permission dialog appear and accept it
- Toggle the Health sync switch on if a Health permission dialog appears and
  accept it

**Progress screen**

- Scroll through the weight trend and intake charts

## Notes for the recording

- One uncut take, portrait only
- Make every tap deliberate; give each screen a moment to settle
- No personal data: use initials in onboarding, no real email
- Stop the recording from Control Center; it saves to Photos

## Delivery

AirDrop or email the video (or upload to a file share and send the link). It
will be attached in App Store Connect under the review conversation
(Resolution Center → reply to Apple's request) as an .mp4.

## Cleanup after review is approved

The API key used in the recording must be **revoked by the owner** — notify
them when the video is delivered.
