# Runbook: helpdesk mailboxes (Microsoft 365 and IMAP/SMTP)

See [ADR 0054](../adr/0054-helpdesk-mailboxes.md). A company can have several helpdesk mailboxes.
Each is one of:

| Kind | For | Signs in with |
|---|---|---|
| Microsoft 365 (Exchange Online) | mailboxes in Microsoft 365 | an application registration (client secret) |
| IMAP and SMTP | Exchange Server on-premises, other mail servers | user name and password |

The settings are entered in the app (Helpdesk > Settings > Mailboxes, needs `helpdesk.admin`).
The password or client secret is **not** entered in the app: it is an environment variable of the
worker. Mail is fetched and sent by the worker, so it must run (the app warns administrators
when it does not, ADR 0052).

## Microsoft 365 mailbox

1. **Register an application** in the Microsoft Entra admin centre: Identity > Applications > App
   registrations > New registration. Single tenant; no redirect URI.
   Note the **Directory (tenant) ID** and the **Application (client) ID**.
2. **Permissions:** API permissions > Add a permission > Microsoft Graph > *Application
   permissions* > `Mail.ReadWrite` and `Mail.Send`. Then *Grant admin consent*.
   Delegated permissions do not work: the worker signs in without a user.
3. **Restrict the application to the helpdesk mailboxes.** With the permissions of step 2 alone it
   can read and send as every mailbox of the tenant. Choose one of two ways; they are not
   combined.

   *RBAC for Applications (recommended by Microsoft).* RBAC does **not** narrow the tenant-wide
   Entra permissions of step 2: it only adds what the application may do, scoped. So for this
   way, **remove** `Mail.ReadWrite` and `Mail.Send` (and their admin consent) from the app
   registration, and give the application the Exchange roles *Application Mail.ReadWrite* and
   *Application Mail.Send* through a service principal and a management scope that holds only the
   helpdesk mailboxes (Exchange Online PowerShell: `New-ServicePrincipal`,
   `New-ManagementScope`, `New-ManagementRoleAssignment`; see Microsoft's "Role Based Access
   Control for Applications in Exchange Online"). Leaving the Entra grants in place keeps the
   whole tenant open.

   *Application access policy (the older way).* Keep the Entra permissions of step 2 and limit them
   in Exchange Online PowerShell, with a mail-enabled security group that holds the helpdesk
   mailboxes:

   ```powershell
   New-ApplicationAccessPolicy -AppId <client id> -PolicyScopeGroupId helpdesk-mailboxes@contoso.com `
     -AccessRight RestrictAccess -Description "tradocraft helpdesk"
   Test-ApplicationAccessPolicy -Identity support@contoso.com -AppId <client id>     # Granted
   Test-ApplicationAccessPolicy -Identity someone.else@contoso.com -AppId <client id> # Denied
   ```

   A change can take up to an hour to apply.

   **Verify the scope** whichever way you chose, once the secret of step 4 exists: get a token for
   the application (client credentials, scope `https://graph.microsoft.com/.default`) and call
   Graph with it. `GET /users/support@contoso.com/mailFolders/inbox/messages?$top=1` must work;
   the same call for a mailbox outside the scope (`someone.else@contoso.com`), and a
   `POST /users/someone.else@contoso.com/sendMail`, must fail with HTTP 403. If either succeeds,
   the application can still use other mailboxes: fix step 3 before going on.
4. **Create a client secret:** Certificates & secrets > New client secret. Copy the *Value* (not
   the Secret ID). Note when it expires and put a reminder in the calendar: when it expires,
   fetching and sending stop and the app shows the sign-in error on the mailbox.
5. **Give the secret to the worker** as `MAILBOX_SECRET_<NAME>`, where `<NAME>` is the "Name of the
   secret" you will enter in the app (upper-case letters, digits and underscores), for example in
   `docker-compose.yml` or the worker's `.env`:

   ```yaml
   worker:
     environment:
       MAILBOX_SECRET_SUPPORT: "the client secret value"
   ```

   Bind the secret to its company, otherwise the worker refuses to use it:
   `MAILBOX_BIND_<NAME>` holds the id of the company that owns the secret. Another company that
   enters the same secret name in the app gets nothing.

   ```yaml
       MAILBOX_BIND_SUPPORT: "<company id>"
   ```

   Restart the worker. One application can serve several mailboxes: give them the same secret name.
6. **Add the mailbox in the app:** connection *Microsoft 365 (Exchange Online)*, the mailbox's
   address (a shared mailbox works; it needs no licence of its own for this), tenant ID,
   application ID, name of the secret (`SUPPORT`), and the team new tickets should start in.
   Mark one mailbox as the default: system e-mail (portal login links, SLA notices) and replies
   on tickets without a mailbox leave through it.

Within one worker pass (`POLL_SECONDS`, 30 s by default) the mailbox shows "E-mail last fetched
on ...", or the reason it failed.

## IMAP/SMTP mailbox (Exchange Server on-premises and others)

1. On Exchange Server, IMAP4 must be enabled and started (it is off by default) and the mailbox
   must be allowed to use it; SMTP submission needs a receive connector that accepts
   authenticated clients (port 587, STARTTLS).
2. Give the password to the worker as `MAILBOX_SECRET_<NAME>`, and bind it to the company and the
   servers it may be sent to with `MAILBOX_BIND_<NAME>=<company id>:imap.example.com,smtp.example.com`.
   The worker never sends a password to a server that is not listed, whatever is entered in the
   app. Restart the worker.
3. Add the mailbox in the app: connection *IMAP and SMTP*, user name, IMAP server (port 993 with
   TLS by default; IMAP without TLS is only accepted for a server on the same machine), folder (`INBOX`), SMTP server, port and encryption (587 STARTTLS, 465 TLS),
   and the name of the secret. Switch "Fetch incoming e-mail" off for an address that only sends.

Exchange Online does not accept this kind: it refuses password sign-in. Use the Microsoft 365
kind.

## What the mailbox line in the app means

The wording of Microsoft's own messages can differ; the HTTP status is the reliable part.

| Shown | Meaning | Do |
|---|---|---|
| E-mail last fetched on ... | the last pass worked | nothing |
| No e-mail fetched yet | the worker has not tried: it is not running, or this is not a live environment | check the worker banner; see below for test environments |
| ... the worker has no MAILBOX_SECRET_X variable, or MAILBOX_BIND_X does not allow this company and server | the secret is not set on the worker, or its binding is missing or names another company or server | set both, restart the worker |
| signing in to Microsoft 365: HTTP 401 ... Invalid client secret | wrong or expired secret | create a new secret (step 4), update the variable |
| signing in to Microsoft 365: HTTP 400 ... tenant ... not found | wrong tenant ID | correct it in the app |
| listing unread mail: HTTP 403 ... Access is denied | permissions or admin consent missing, or the access policy excludes this mailbox | steps 2 and 3 |
| listing unread mail: HTTP 404 | the address is not a mailbox of this tenant | correct the address |
| HTTP 429 (retry after N s) | Microsoft throttles the application | wait; the next pass tries again |
| IMAP login / connecting to IMAP server | wrong user, password, server or port, or IMAP is off | step 1 of the IMAP section |

A reply that could not be sent shows its reason on the message in the ticket and is tried five
times. It is never sent through another mailbox than its own.

## How mail is routed

- A new e-mail becomes a ticket in the team of the mailbox it arrived in (else the default team).
- A reply is sent from the mailbox the ticket came in on. If that mailbox was removed or switched
  off, from the default mailbox.
- The same e-mail sent to two helpdesk addresses becomes one ticket.
- Removing a mailbox keeps its tickets.
- A company without mailboxes keeps using the worker's `IMAP_*`, `SMTP_*` and `MAIL_TRANSPORT`
  variables.

## Test and tutorial environments

Outside a live environment nothing is sent through a mailbox (e-mail is written to files) and
nothing is fetched ([ADR 0048](../adr/0048-environment-clones-and-outbound-safety.md)).
`envctl clone` also switches every mailbox off in the clone. To try a mailbox in a test
environment, use a **dedicated test mailbox**: change the address in the clone, switch the mailbox
on, give the clone's worker the secret and `ALLOW_INBOUND_MAIL_IN_NON_LIVE=1`. Fetching marks
mail as read in that mailbox. Sending stays off in every non-live environment.

## Check once after setting up a Microsoft 365 mailbox

The Graph connection is tested in the code against a stand-in, not against Microsoft. Do this
once with a test mailbox before pointing customers at it:

1. Send an e-mail with an attachment (PDF or picture) to the mailbox. Within a pass it is a ticket
   in the right team, the attachment is on it, and the e-mail is marked read in Outlook.
2. Reply from the ticket with an attachment. It arrives, from the mailbox's address, and is in
   the mailbox's Sent Items.
3. Answer that reply from the customer's side. It lands on the same ticket, not a new one.
4. Change the subject of a further answer so the ticket number is gone. It still lands on the
   same ticket (threading by Message-ID).
5. Request a portal login link. It arrives from the default mailbox.
