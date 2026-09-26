# Privacy policy – pure-nvim calendar

pure-nvim is a personal Neovim configuration. Its calendar module
(`lua/pure/calendar.lua`, `lua/pure/gcal.lua`) connects to Google Calendar
only on the computer where it runs, for the person who authorizes it.

- **What it accesses:** the events and the list of calendars of the Google
  account that authorizes it, to show them in notes and to create, change or
  delete the events that person edits there.
- **Where the data goes:** nowhere else. Requests go straight from that
  computer to Google's API. There is no server, no analytics and no third
  party; nothing is collected, sold or shared.
- **What is stored:** on that computer only, in Neovim's data folder: the
  OAuth client ID and secret, the refresh token Google issues, and a copy of
  the last events written into the notes (to tell edits apart). The notes
  themselves hold the events shown in them.
- **Removing access:** delete `google_calendar.json` from Neovim's data folder
  and revoke the app at <https://myaccount.google.com/permissions>.

Contact: the owner of this repository, through GitHub.
