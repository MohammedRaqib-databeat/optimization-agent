# Project Handoff: AI Campaign Operations Platform on Salesforce Media Cloud

Read this whole file before doing anything else in this project. It captures everything built, decided, and learned across the full build session so far. This is the **second** handoff document — sections 1-8 are largely carried forward from the first handoff (still accurate), sections 9+ are new since then.

---

## 1. The Vision (what the org is building)

An enterprise AI-powered Campaign Planning and Media Operations platform on Salesforce Media Cloud, meant to be packaged and sold on the **Salesforce AppExchange** to publishers/SSPs (Nexstar, CW, Versant, Inmobi, etc.), who will resell it to their own advertiser clients.

End to end flow the platform automates:
**Advertiser request (Form/Email/OMS) → Case → Validation Agent → Lead/Account/Contact → Opportunity → Product Selector Agent → Forecast/Availability check → Media Plan (Quote/AdQuote) → Optimization Agent (continuous) → Human approval → Order → Order Push to GAM/FreeWheel → two-way sync back into Salesforce.**

**Hard constraint from Salesforce solution architects on the team: zero new custom objects.** Everything must be built on standard Salesforce objects plus custom fields, permission sets, and Apex. Followed strictly throughout, including in this session's new work.

**Critical realization from the first session, still true:** real users of this tool never type a Line Item ID. They ask things like "how is Nike performing" or "is the Nike order on track." The agent is built around name-based lookup with disambiguation, not ID-based lookup.

**New context this session:** the user's manager has now framed the real end goal explicitly — this needs to work for **many different client organizations installing from the AppExchange, most of whom have zero technical staff who could ever run a CLI command or convert a certificate manually.** Every remaining piece of work (especially the GAM connector) has to be judged against "would a completely non-technical client admin be able to do this alone."

---

## 2. The Org

- Alias: `MYORG`. sfdx-project.json exists, `force-app/main/default` is the source root. **This is not a git repository** (confirmed via `git status` → "fatal: not a git repository") — there is no version control here, only the local filesystem. Be careful with anything destructive; there's no `git stash`/`git reset` safety net.
- Real Salesforce Media Cloud ASM data model natively provisioned (not a package). Native objects in use: `AdQuote`, `AdQuoteLine`, `AdOrderItem`, `AdOrderLine*`, `MediaChannel`, `AdServer`, `AdServerAccount`, `AdSpace`, `AdSpaceSpecification`, `AdSpaceCapacity`, plus standard `Quote`, `QuoteLineItem`, `Order`, `OrderItem`, `Account`, `Contact`, `Lead`, `Opportunity`, `Case`, `Product2`, `Pricebook2`.
- **Environment quirks (updated this session):**
  - Bash tool chokes on `sf` due to the space in `C:\Program Files\sf\...` — use PowerShell for `sf data query`/`sf org ...`, Bash is fine for `sf project deploy start`/`sf apex run`.
  - Git Bash (MSYS) mangles `openssl` arguments starting with `/` (e.g. `-subj "/CN=..."`) by treating them as Windows paths. Fix: prefix the command with `MSYS_NO_PATHCONV=1`.
  - **No JDK was installed on this machine.** `keytool` (needed for PKCS12→JKS conversion) requires a real JVM. Chocolatey install failed (needs admin elevation, this session's shell isn't elevated). Worked around by downloading a **portable Temurin 17 JDK zip** directly from `https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse` and extracting it locally — no install/admin rights needed, `keytool.exe` is at `<extracted>/bin/keytool.exe`.
  - `sf apex run` (execute anonymous via CLI) **ignores TraceFlags/DebugLevels** — always logs at a fixed low level (`APEX_CODE,DEBUG;APEX_PROFILING,INFO`), regardless of a TraceFlag configured for the running user. If you need full `Callout=FINEST` detail, you cannot get it through `sf apex run`; the underlying saved `ApexLog` also respects this same fixed level for API-invoked executeAnonymous. Diagnosing callout-level issues instead required raw `HttpRequest`/`Http.send()` test scripts printing `res.getBody()`/`res.getHeaderKeys()` directly.
  - **Salesforce's Metadata API and Tooling API `Certificate` object have zero fields for private key/keystore material** (confirmed via live `FieldDefinition` query — only `Id, CreatedDate, DeveloperName, ExpirationDate, KeySize, MasterLabel, CertificateChain, Options`). Importing a private key into Salesforce's Certificate and Key Management store is **only possible through the interactive Setup UI** ("Import from Keystore") — no API, no Metadata API deploy, no Tooling API insert can do this. This is a hard, deliberate Salesforce security boundary, confirmed by direct testing, not assumption. Same applies to `ExternalCredential` — confirmed `NOT_FOUND` when describing it as a Tooling API SObject; it's Metadata-API/UI-managed only, not directly insertable via Apex DML.
  - Salesforce's Setup → Certificate and Key Management → "Import from Keystore" **only accepts genuine JKS format, not PKCS12** — confirmed by direct test (`.p12` upload → "Error: Keystore file is corrupted"). There is **no reliable JavaScript or Python library that writes real JKS files** (only reading is well-supported, e.g. `pyjks`, `jks-js`) — `keytool` (a real JVM) remains the only trustworthy way to produce one. This shapes the whole automation architecture in §10 below.
  - `agentscript.txt` (repo root) is a **local reference/design document only**, not deployable Salesforce metadata by itself — but its content is 1:1 identical to the real deployable Agent Script file at `force-app/main/default/aiAuthoringBundles/Campaign_Forecasting_Agent/Campaign_Forecasting_Agent.agent` (see §6 for the newer Agentforce DX / `sf agent` CLI workflow that supersedes manual copy-paste for most of the script).

---

## 3. Architecture Principle Followed Throughout

**Apex = deterministic evidence engine. Agent (Atlas) = interpretation and explanation only. Human = approval for anything consequential.**
Apex never invents a value, never selects a "final recommendation," never applies a change without explicit confirmation. Still true, and now extended: this session added the platform's first **real write path** (the Optimization Agent's "Apply Suggestion" feature, §5), and it was built to preserve this principle exactly — Apex only ever creates a **Draft** Quote Line Item, never a live Order, and only ever after a human clicks a native Confirm button.

---

## 4. Agentforce DX Workflow (new this session — supersedes manual copy-paste for most work)

Discovered and validated a full CLI-based workflow for editing/testing/publishing the agent, instead of only pasting `agentscript.txt` into the browser:

- **The org already has a real `AiAuthoringBundle`** called `Campaign_Forecasting_Agent`, retrievable via `sf project retrieve start --metadata "AiAuthoringBundle:Campaign_Forecasting_Agent"`, landing at `force-app/main/default/aiAuthoringBundles/Campaign_Forecasting_Agent/Campaign_Forecasting_Agent.agent`. This file's content matches `agentscript.txt` byte-for-byte after edits are kept in sync.
- **`sf agent validate authoring-bundle --api-name Campaign_Forecasting_Agent --target-org MYORG`** — validates the script compiles, entirely locally/API-driven, no browser needed.
- **`sf agent preview start/send/end --authoring-bundle Campaign_Forecasting_Agent --target-org MYORG --use-live-actions`** — a genuine, scriptable, non-interactive way to have a real conversation with the agent (using real Apex, not simulated) directly from the terminal. Used successfully to verify Forecasting/Optimization/Rollup behavior without touching the browser at all.
- **`sf agent publish authoring-bundle`** — exists, but has real limitations (see §5's GAM story about `Apply_Optimization_Suggestion`): it validates the *entire* agent, including pre-existing unrelated schema drift on other actions (e.g. `Optimize_Campaign_From_Historical_Delivery`'s registered output schema is stale relative to current Apex), and a schema-less metadata deploy of a `genAiFunctions/*` folder for an action **corrupts** an already-good UI-created action (this happened once, had to delete the corrupted `GenAiFunctionDefinition` record via Tooling API and recreate cleanly). **Net advice: use `sf agent validate`/`preview` freely from the CLI; be very cautious with `sf agent publish` and with deploying `genAiFunctions/*` metadata for any action that was originally created via the UI's Apex-action picker** — prefer creating/editing actions through **Agentforce Asset Library** (Setup → Agentforce Studio → Agentforce Asset Library → Actions tab → **New Agent Action**), which is confirmed to correctly generate complete input/output schema, unlike the topic-level "Add Action → New Action" dialog which silently failed to persist at all in one real instance this session (the action appeared in the topic tree but had zero backing `GenAiFunctionDefinition` record — verified via direct Tooling API query, not assumption).

---

## 5. Optimization Agent — Human-in-the-Loop "Apply Suggestion" Feature (new this session, fully built and verified working end to end)

This is the platform's first real write action, and it's genuinely live and tested.

**New Apex:**
- **`CampaignSuggestionApplicationService.cls`** — given a source (CSV-backed) Line Item ID, advertiser name, and a plain-English suggestion summary, find-or-creates the minimal `Account → Opportunity → Quote → AdQuote` chain (none of this exists yet for the CSV-simulated advertisers, since they're not real CRM Accounts), then inserts a **Draft** `QuoteLineItem`/`AdQuoteLine` describing the suggestion. Reuses the same Quote across multiple confirmed suggestions for the same line item (verified: 2 confirmed suggestions → 1 Quote, 2 Quote Lines).

**New Agentforce action:** `Apply_Optimization_Suggestion`, registered with `isConfirmationRequired = true` — this is what produces the real native Confirm/Cancel card in Agentforce preview/conversation. **Getting this action correctly registered was the single biggest time sink this session** — see the "Agentforce action registration gotchas" note in §4 above. The action that finally worked was created via **Agentforce Asset Library**, not the topic-level dialog.

**agentscript.txt / the `.agent` file changes:**
- `Campaign_Optimization` subagent's `Recommended Next Steps for Human Review` section now explicitly requires literal numbered output (`1. ...`, `2. ...`) **in the section itself**, not just in a separate later instruction — the earlier version had the numbering rule in the wrong place (a later "OFFERING TO APPLY A SUGGESTION" section) and the model reliably ignored it until the rule was moved to where the list is actually generated.
- Full instructions added for calling `Apply_Optimization_Suggestion` once per confirmed suggestion (never batched), never claiming a change happened until the result confirms success.
- **Verified working end to end**, live, multiple times: numbered report → "apply suggestion 2" → real native Confirm/Cancel card renders → on Confirm, real `Account`/`Opportunity`/`Quote`/`QuoteLineItem` created in Salesforce (checked directly in the UI, not just trusted the agent's claim).

**Two real bugs found and fixed in existing code this session** (unrelated to the write-path feature, found while testing it):
- `CampaignEntityResolutionService.findMatchingKeys()` matching was one-directional (`key.contains(searchLower)` only) — "Advertiser 007 lifetime campaign" failed to resolve while bare "Advertiser 007" worked. Fixed to match both directions.
- The resolver never returned the **actual Line Item IDs** behind a multi-match advertiser/order — only a count. The agent was inventing placeholder IDs ("Line Item ID 1") or, worse, hallucinating a fake-but-real-looking ID in one observed case. Fixed by adding a real `candidateLineItemIds` output field.

---

## 6. GAM Connector — Full Real Authentication, Verified Live (the other major piece of this session)

**Status: genuinely working, verified with a real live API call returning real network data.** This was not simulated or assumed — confirmed via a real SOAP call to `NetworkService.getCurrentNetwork()` returning:
```
NETWORK DISPLAY NAME: DataBeat Consulting Private Limited
NETWORK CODE: 23201882692
CURRENCY: USD
TIME ZONE: America/New_York
```

### What exists in the org right now (single-tenant, this org only — see §10 for the multi-tenant automation problem)

- **Certificate**: `gam_service_account_key` (Self-Signed, imported via Setup → Certificate and Key Management → Import from Keystore, from a manually-converted JKS).
- **External Credential**: `GAM API Cred OAuth` — **Authentication Protocol: `OAuth 2.0`, Authentication Flow Type: `JWT Bearer Flow`** (this exact combination matters, see the pitfall below). Identity Provider URL: `https://oauth2.googleapis.com/token`. Scope: `https://www.googleapis.com/auth/dfp`. JWT Claims: `iss` = the service account's `client_email`, `aud` = `https://oauth2.googleapis.com/token`, plus a manually-added custom claim `scope` = `https://www.googleapis.com/auth/dfp` (critical, see pitfall below), plus Salesforce's own auto-generated `exp`/`iat`/`nbf`/`alg`/`typ`.
- **Principal**: `GAM_Integration_Principal_OAuth` (Named Principal).
- **Named Credential**: `GAM_API`, URL `https://ads.google.com/apis/ads/publisher/v202608` (note the version — GAM's current live API version as of this session; **v202408, which appeared in older reference material, is already sunset** — always check `https://developers.google.com/ad-manager/api/rel_notes` before hardcoding a version).
- **Apex**: `GAMNetworkServiceStub.cls` + `AsyncGAMNetworkServiceStub.cls` (WSDL2Apex-generated from `NetworkService.wsdl`, hand-patched, see pitfall below) + `GAMNetworkServiceClient.cls` (thin wrapper exposing `getCurrentNetwork()`).
- **There is also an earlier, broken, now-abandoned External Credential** called `GAM API Cred` (Authentication Protocol: plain `JWT`, not `OAuth 2.0`) — **do not use or resurrect this one**, see pitfall #1 below for exactly why it's wrong. It can be deleted; nothing references it after the Named Credential was repointed to `GAM API Cred OAuth`.

### Real values (safe to reference, not secret beyond the private key itself)
- Service account email: `db-gam@db-data-analyst-training.iam.gserviceaccount.com`
- GCP project: `db-data-analyst-training`
- GAM network code: `23201882692`
- The original JSON key file (`db-data-analyst-training-a5a58295956b (1).json`) **was accidentally deleted from the repo root during cleanup** — flagged to the user immediately; if a fresh key is ever needed, it must be regenerated from Google Cloud Console (IAM & Admin → Service Accounts → that account → Keys), since Google never re-issues the same private key.

### The two real pitfalls that cost the most time (read these before touching GAM auth again)

1. **Salesforce's plain `JWT` Authentication Protocol is NOT the same as Google's OAuth JWT Bearer flow.** The bare `JWT` protocol type signs a JWT and sends **that raw JWT itself** as the `Authorization: Bearer` header — no exchange step. Verified this exact behavior by pointing the Named Credential at `httpbin.org/headers` and inspecting the literal header Salesforce sent: it was our own signed assertion, unexchanged. Google's Ad Manager API requires the **real OAuth 2.0 two-legged exchange** (POST the JWT to `https://oauth2.googleapis.com/token`, get back a real opaque `access_token`, use *that* as Bearer). **The fix is Authentication Protocol = `OAuth 2.0`, Authentication Flow Type = `JWT Bearer Flow`** — a different, correct configuration that actually performs the exchange.
2. **Even with the correct `OAuth 2.0` + `JWT Bearer Flow` combination, the exchange failed with `invalid_scope`** until a `scope` claim was manually added to the JWT body. Salesforce's "Scope" field on the External Credential form does **not** automatically embed a `scope` claim inside the signed JWT for Google's flow — it has to be added as an explicit custom JWT Body Claim. Diagnosed by manually re-building the exact same JWT in Apex (`Crypto.signWithCertificate('RSA-SHA256', ...)`) and POSTing it directly to Google's token endpoint — got a real `200`/`access_token` back with a **minimal** claim set (`iss`, `scope`, `aud`, `exp`, `iat` — no `sub`, no `kid`, no `nbf`), which proved the certificate/service-account/scope were all correct and isolated the problem to Salesforce's auto-generated claims specifically missing `scope`.

### WSDL2Apex generation gotcha (Google Ads-family WSDLs specifically)
Any WSDL-generated class literally named `*Exception` (here: `ApplicationException` and `ApiException`, both plain data classes, never actually thrown) fails to compile with `Exception class must extend another Exception class`, because Apex's compiler special-cases anything ending in "Exception". **Fix: rename them** (to e.g. `ApplicationExceptionInfo`, `ApiExceptionInfo`) — safe as long as you first confirm (via `grep`) that nothing else in the generated file references them by name, which was true here.

---

## 7. Multi-Tenant GAM Onboarding Automation (both JKS conversion AND Phase 2 auto-provisioning now fully working, pure-Apex, zero external infrastructure)

**The problem this solves:** everything in §6 was done manually by a technical person (multiple `openssl`/`keytool` commands, multiple failed configuration attempts, deep debugging). A real AppExchange client's admin cannot do any of that. The user's manager explicitly wants **every future client onboarding to be self-service**, with the hard requirement that **no one — not the client's own broader team, and not the ISV's own team — should ever be able to view a client's raw service account secret.**

**Research-backed decision on the overall approach (validated against real published guidance, not just internal preference):** stick with the **per-client service-account model** (not a shared OAuth "log in with Google" consent flow) — a specific published source on real GAM add-ons states "GAM add-ons that authenticate using a read-only service account are generally safe and meet most publisher security standards," while OAuth-against-a-human-admin's-account is flagged as needing *more* security scrutiny, not less. This matches how enterprise IT actually prefers to grant/audit/revoke API access (their own GCP IAM console) over trusting a third-party app with an OAuth grant tied to one employee's login.

**Critical architectural pivot mid-project:** the user's manager and VP explicitly required **everything be done inside Salesforce itself — no Python, no ngrok, no external microservice, no custom hosting of any kind.** This invalidated an already-built external Node.js/Docker conversion microservice (deleted from the repo — `gam-key-conversion-service/` no longer exists) and required building a JKS (Java KeyStore) binary-format writer entirely in Apex, since Salesforce's Setup UI only accepts genuine JKS files (confirmed via direct test: PKCS12 is rejected with "Keystore file is corrupted") and no API exists to upload a keystore programmatically (see §2) — the JKS itself has to be handed to the client pre-built.

### What's built so far (fully working, deployed, and validated)

- **`GAMJKSBuilder.cls`** (deployed) — a pure-Apex JKS writer with zero external dependencies. Given a client's pasted service-account JSON, it:
  1. Extracts the PKCS8 private key and parses its RSA modulus/exponent using a hand-rolled minimal ASN.1/DER reader (Apex Blobs aren't byte-indexable, so all parsing/building is done on hex strings).
  2. Builds a minimal self-signed X.509 certificate for that key pair entirely from scratch — constructs the TBSCertificate DER structure and signs it via `Crypto.sign('RSA-SHA256', tbsBytes, privateKeyBlob)`, using the client's own pasted private key directly as a raw Blob (never imported into Salesforce as a Certificate object first).
  3. Encrypts the private key using Java's proprietary JKS key-protection algorithm (SHA-1-chained keystream cipher, DER-wrapped `EncryptedPrivateKeyInfo` with OID `1.3.6.1.4.1.42.2.17.1.1`) and assembles the full binary JKS container, including the whole-file "Mighty Aphrodite" SHA-1 integrity hash.
  - **Validated end-to-end against real OpenJDK `keytool`** (dev-time only — see `.dev_jks_validation/`, never shipped): generated a JKS from a throwaway test key using this Apex class, confirmed `keytool -list -v` parses it correctly (right cert, right algorithm, right entry type), then round-tripped it to PKCS12 and confirmed the recovered private key's RSA modulus is byte-identical to the original — proving both the container format and the encryption algorithm are correct, not just superficially well-formed.
  - The algorithm was first prototyped and validated in a throwaway Python script (`jks_writer_prototype.py`, dev-time reference only, not shipped) before being ported to Apex, to iterate on the binary format quickly before committing to Apex's more awkward byte-manipulation model.
- **`GAMKeyConversionController.cls`** (deployed) — now calls `GAMJKSBuilder.build()` directly. No callout, no Named Credential, no external service of any kind. Still never logs, persists, or stores the key material.

**Phase 2 — auto-provisioning after the manual keystore import (deployed and validated this session):**

Salesforce's `ExternalCredential`/`NamedCredential`/`PermissionSet` metadata types have no Tooling API insert support and no native `Metadata.*` Apex wrapper class, so the only path to creating them from Apex is a real Metadata API deploy. Two hard technical unknowns were de-risked before committing to the build, both confirmed working via direct test rather than assumption:
- **Can an Apex-obtained session ID authenticate a callout back to the org's own Metadata API?** Yes — `UserInfo.getSessionId()` used as the SOAP session header on a raw `HttpRequest` to `https://{org domain}/services/Soap/m/{version}` returns a real, valid response (tested with `describeMetadata()`), with no Remote Site Setting needed since it's the org calling itself.
- **Can Apex build a valid ZIP file for the deploy payload, given Apex has no compression/deflate API?** Yes — the ZIP spec allows uncompressed ("Stored", method 0) entries, so `ApexMinimalZip.cls` (new) hand-builds the local file headers, central directory, and end-of-central-directory record, including a from-scratch CRC-32 implementation (all done on hex strings, same pattern as `GAMJKSBuilder`, since Apex Blobs aren't byte-indexable). Validated by generating a real ZIP from Apex and confirming `unzip -t` reports no CRC errors and file contents extract correctly.

With both proven, **`GAMOnboardingProvisioningService.cls`** (new) does the real work:
1. Builds the `ExternalCredential` (`GAM_API_Cred_OAuth`), `NamedCredential` (`GAM_API`), and `PermissionSet` (`GAM_API_Access`) metadata XML in memory — templated from the exact working configuration retrieved from this org (see §6), with only the `iss` JWT claim swapped to the new client's own `client_email`.
2. Zips it with `ApexMinimalZip`, submits it via a raw SOAP `deploy()` call using the running admin's session, and exposes `checkStatus()` for polling.
3. `assignPermissionSet()` grants the running admin the External Credential principal access via plain `PermissionSetAssignment` DML (no metadata deploy needed for this part — it's a normal insertable sObject).
4. `discoverNetwork()` (in `GAMNetworkServiceClient.cls`) auto-detects the client's GAM network code. This required finding the one GAM SOAP operation that doesn't require a network code up front — `getCurrentNetwork()` fails with `AuthenticationError.NETWORK_CODE_REQUIRED` when the header is blank (confirmed via direct test), but `getAllNetworks()` works with no network code supplied, exactly the "first login, don't know my own network code yet" scenario. The detected code is persisted to a new **`GAM_Config__c`** hierarchy custom setting (`Network_Code__c` field), replacing the old hardcoded `NETWORK_CODE` constant so each client's install gets its own value with zero manual configuration.
5. All three steps are called as separate Apex round trips from the LWC (`startProvisioning` → poll `checkStatus` → `assignPermissionSet` → `discoverNetwork`), not chained in one transaction, because Salesforce forbids a callout in the same transaction as a preceding DML statement (`discoverNetwork` does a callout; `assignPermissionSet` does DML) — hit this exact governor error during testing and split the calls to fix it.

**Full pipeline re-verified end-to-end in the live org**: ran the real deploy against this org's own `GAM_API_Cred_OAuth`/`GAM_API`/`GAM_API_Access` (safe test since the content matches the already-working config), confirmed the deploy succeeded, then confirmed `GAMNetworkServiceClient.getCurrentNetwork()` still returns real live GAM data afterward — proving the automated redeploy didn't break the working connection, and that `discoverNetwork()` correctly detects and persists the real network code (`23201882692`, DataBeat Consulting Private Limited).

- **`gamOnboardingWizard`** LWC (deployed) — the "I've Imported It - Continue" button now runs the real Phase 2 flow (a spinner with status text through provisioning → permission grant → network discovery), ending on a "connected" screen showing the detected network name and code. No more placeholder toast.

### What's genuinely NOT possible to automate (confirmed via direct API testing, not assumption)
- The literal "Import from Keystore" click in Setup — no Metadata API or Tooling API field exists for uploading a private key/keystore (see §2). This is a permanent, one-click, per-client, human action. No workaround exists on the Salesforce platform.
- A client's own IT admin adding your service account as an authorized user inside **their own** GAM Admin panel — has to happen on Google's side, by someone with GAM Admin access at the client's company.
- A client generating their own service account JSON in Google Cloud Console in the first place.

### What's still open (pick up here)
1. **Test the full wizard live, start to finish, with a genuinely fresh/throwaway GAM service account** (not just the safe idempotent redeploy-over-working-config test done this session) to confirm the flow works for a client whose `ExternalCredential`/`NamedCredential`/`PermissionSet` don't exist yet at all — this session's test only proved the deploy mechanism works, not the true first-time-create path in an org that starts with none of this metadata.
2. **Clean up `.dev_jks_validation/`** once no longer needed for regression-checking future changes to `GAMJKSBuilder.cls`/`ApexMinimalZip.cls` — it holds a portable JDK (`keytool`) that is explicitly dev-time-only and must never ship.
3. Consider adding Apex test classes for `GAMJKSBuilder`, `ApexMinimalZip`, and `GAMOnboardingProvisioningService` (a throwaway fixture PEM key would be needed as test data, since Apex can't generate RSA keys) to protect this logic under CI/regression going forward.
4. The `GAMOnboardingProvisioningService` deploy currently has no automatic retry/rollback UX beyond surfacing the error message — worth deciding whether a failed mid-flow provisioning attempt (e.g., network blip during the SOAP callout) needs a "resume from here" path rather than starting the whole wizard over.

---

## 8. Metrics Decisions (carried forward from first handoff, unchanged this session)

**Full technical metric set** (deep-dive Forecast/Optimization reports): Impressions, Clicks, Revenue, Code Served Count, Unfilled Impressions, CTR%, CPM, Fill Rate%, portfolio medians, versus-benchmark %, descriptive signals, Optimization Health/Urgency, Goal Type/Units, targeting dimensions, Contention (Priority, Status only).

**Minimal POC metric set for non-technical order health checks**: Delivery Pacing, Fill Rate, CPM only.

**Explicitly removed from the whole org** (per direct user request, prior session): Viewability (top-level only), Frequency Cap, Booked Rate/Cost Per Unit, Competitive Exclusion Group.

`Demo_required_metrics.xlsx` (repo root, colleague's mapping sheet) — 23 rows total, rows 17-23 added/verified this project, rows 2-16 are the colleague's original content and **must never be edited** without explicit fresh authorization (this was a hard scope boundary the user enforced strictly in an earlier session).

---

## 9. Two Published Artifacts (research references, still live, unchanged)

1. **"Ad Server Metrics Field Guide"** — GAM + FreeWheel metrics for forecasting/optimization.
2. **"From Traffic Sheets to Trading Agents"** — media ops org structure, product catalog, industry timeline, skepticism section.

---

## 10. Genuinely Blocked / Open Items

1. **GAM connector for the *current* org — DONE, verified live** (§6). The remaining GAM-related work is entirely about **multi-tenant automation** for new AppExchange clients (§7), not about getting this org connected.
2. **Hosting decision for `gam-key-conversion-service`** — needs the user to pick Option A (ngrok, fastest) or Option B (Cloud Run, more durable) from §7.
3. **Phase 2 auto-provisioning engine** — not started, real design decision needed (deep-linked manual screens vs. full Metadata-API-deploy-from-Apex).
4. **Real Approval Process** — still just a `Quote.Status` field check, needs a named approver before it can be built declaratively.
5. **Two Order Health Check thresholds** (pacing ≥90%, fill rate ≥70%) — still unvalidated POC defaults needing business sign-off.
6. **Optimization Agent's fuller scheduler-driven vision** (from the manager's task list this session: underperformance thresholds, scheduler/trigger after stats sync, decision logic, Order Push Connector, audit log) — explicitly deprioritized until real GAM data replaces the CSV simulation, since several of these tasks are meaningless against fake data. Now that §6 proves GAM auth genuinely works, this is unblocked whenever the user wants to pursue it — building a real `CampaignDataProvider` implementation backed by GAM instead of CSV would be the natural next step before any of these.
7. **Recommended Next Steps numbering** — fixed and verified working (§5), but keep an eye on it; this class of "instruction in the wrong section of the prompt" bug is easy to reintroduce when editing the agent script.

---

## 11. Key Behavioral/Style Preferences Learned From This User (carried forward + new this session)

- **No em dashes or en dashes anywhere**, in code comments, chat responses, or documents.
- Plan first, execute after a clear "go ahead" — still the working rhythm, though this session the user increasingly said "just do it fast" once trust was established on a given thread of work.
- Wants everything **verified in the live org**, not just "should work" — this was followed extremely strictly this session (e.g. the entire GAM debugging process was built on real HTTP response inspection, not guessing).
- Wants honest flagging of "this is a default, not validated" and "this genuinely cannot be automated, here's why" rather than confident-sounding invented claims. This session added a strong new pattern: **when told something is a platform limitation, verify it directly (via a real API call or describe) rather than asserting it from memory or an unverifiable web page** — this was done repeatedly (Certificate/ExternalCredential API fields, JKS-vs-PKCS12 acceptance, JWT-vs-OAuth2-JWTBearerFlow behavior) and was clearly the right call each time, since assumptions going in were sometimes wrong.
- **Very concerned with getting credit/recognition within their organization** for this work — explicitly said so this session ("it helps me in getting recognition in the organization"). Frame work in terms of what makes their output stand out (e.g. "most GAM add-ons don't bother with client-side crypto, this would be genuinely differentiated").
- **Security-conscious about secrets in a way that should be taken literally, not just symbolically** — when a raw private key appeared in the conversation/tool context, this needed to be flagged as a real exposure concern, not brushed past. When cleaning up scratch files, **be very careful about what gets deleted** — accidentally deleted the user's original service account JSON key file during a cleanup pass this session; this should have been confirmed first since it was the user's own file, not a scratch file Claude created.
- Frequently asks for plain-English recaps of "what did we do and why" to relay to colleagues/managers — keep these regenerable from current state, don't rely on stale memory.
- Genuinely appreciates being corrected when Claude's own assumption/architecture recommendation turns out to be wrong for what they actually need (e.g. initially recommended a shared-OAuth-browser-flow architecture for multi-tenant onboarding; the user pushed back that per-client service accounts were the real requirement, and follow-up research confirmed the user's instinct was actually the industry-standard approach, not a compromise) — don't be defensive about this pattern, it's productive.
- **This session ran long enough to fill the context window twice** — the user is proactively asking for this handoff document specifically so a fresh Claude session can pick up cleanly. Read this whole file, then check the actual current state of `.gam_setup_temp`-style scratch folders (should be cleaned up, but verify), the `gam-key-conversion-service/` folder (should exist, not yet hosted), and the LWC/Apex files listed in §7 (should exist, deployed) before assuming anything is stale.

---

## 12. Immediate Next Steps (pick up here)

1. **Resume the GAM onboarding automation hosting decision** — Option A (local + ngrok, fast POC) vs Option B (Google Cloud Run, same existing GCP project, more durable). This was the literal next action when this handoff was requested.
2. Once hosted, create the `GAM_Key_Conversion_Service` Named Credential pointing at the real URL, and test the full `gamOnboardingWizard` LWC flow end to end (paste a test service account JSON → convert → download → manually import → confirm it works).
3. Design and build Phase 2 (auto-provisioning External Credential/Named Credential/Principal/network-code detection after the one manual keystore import).
4. Once GAM auth is proven multi-tenant-ready, revisit the manager's fuller Optimization Agent scheduler-driven task list (§10 item 6) — now technically unblocked.
5. Clean up any remaining scratch artifacts from this session (`.gam_test2/` throwaway PKCS12 test files were left behind due to a file-lock issue — safe to delete, contain no real secrets, just a disposable test certificate).

---

## 13. Intake-to-Order Pipeline + Real GAM Order Push/Delete Connector (new session, fully built and verified live)

**Note:** §§1-12 above are carried forward unchanged from an earlier handoff and are now partly stale (e.g. §10 item 6 and §12 no longer reflect current state) — this section documents what changed since, without rewriting the earlier sections.

### What's now wired together (real Salesforce records at every step, no simulated data)
- **Case → Opportunity auto-chain**: `CampaignCaseTrigger`/`CampaignCaseTriggerHandler` (new, after insert/update on Case) auto-calls `CampaignIntakeService.validate()` then `CampaignIdentityResolutionService.resolve()` when a Case moves to Validated. Verified live: a single Case insert auto-created a real Opportunity.
- **Campaign_Planner subagent** (`agentscript.txt` + mirrored `.agent` bundle) — conversational: `Recommend_Products_for_Opportunity` (read-only ranking) → `Create_Media_Plan_from_Selected_Products` (Draft Quote/AdQuote, human-confirmed) → `Convert_Approved_Media_Plan_to_Order` (Draft Order, human-confirmed, refuses unless Quote is Approved/Accepted). Verified live end to end with real Quote and Order records created via `sf agent preview send`.
- **GAM Order Push/Delete connector (new this session)** — real SOAP integration against the live GAM network (code `23201882692`), built on five newly-generated WSDL2Apex stubs (`GAMCompanyServiceStub`, `GAMOrderServiceStub`, `GAMLineItemServiceStub`, `GAMUserServiceStub`, `GAMInventoryServiceStub`), each hand-fixed for WSDL2Apex's non-flattened-inheritance and reserved-Exception-name bugs (see below).
  - **`GAMOrderPushService.push()`** (`@InvocableMethod`, human-confirmation-gated): finds/creates the GAM Company (by Account Name, cached on new field `Account.GAM_Company_Id__c`), finds/creates the GAM Order (by name), builds GAM Line Items from the Salesforce Order's OrderItems (first ACTIVE Ad Unit in the network, explicit end date since STANDARD line items can't be unlimited-end-date), and writes the resulting GAM Order ID / Line Item IDs back onto the Order's `AdOrderItem` records. All callouts happen before any DML (governor-limit requirement). **Verified live**: pushed Salesforce Order `801dN000012uGq1QAE` → real GAM Order `4204715699` with 2 real Line Items.
  - **`GAMOrderDeleteService.deleteOrder()`** (separate class — Apex allows only one `@InvocableMethod` per class; human-confirmation-gated): deletes the GAM Order recorded on an Order's `AdOrderItem.AdServerOrderIdentifier`. **Had to be implemented as a hand-built raw SOAP HTTP callout** (still routed through the same `GAM_API` Named Credential, so auth is unaffected) rather than through the WSDL2Apex stub's generated port method — see gotcha below. **Verified live**: deleted GAM Order `4204715699`, then confirmed via a real `getOrdersByStatement` query that it returns 0 results.
  - Both actions log to `Optimization_Change_Log__c` (`GAM_ORDER_PUSHED`/`GAM_ORDER_PUSH_FAILED`/`GAM_ORDER_DELETED`/`GAM_ORDER_DELETE_FAILED`) and are wired into the `Campaign_Planner` subagent in `agentscript.txt` with `require_user_confirmation: True`.
  - **Still MVP-level, flagged for later**: creative size is a hardcoded 300x250 placeholder; Ad Unit targeting is "first ACTIVE ad unit in the network," not derived from any real product/AdSpaceSpecification mapping.

### New gotcha discovered this session (read before touching any other GAM write action)
GAM's `performOrderAction` SOAP operation takes an abstract `orderAction` XSD element (subtypes: `DeleteOrders`, `ArchiveOrders`, etc.) that requires an explicit `xsi:type` on the wire. **WSDL2Apex's generated Apex stub cannot serialize this correctly** — neither declaring the wrapper field as the concrete subtype nor overriding the generated `*_type_info` array produced a valid `xsi:type`; GAM kept rejecting the request with `cvc-type.2: The type definition cannot be abstract for element orderAction`. The only fix that worked was bypassing the stub entirely for this one call and POSTing a hand-built SOAP envelope via `Http`/`HttpRequest` (still through `callout:GAM_API/OrderService`, so org auth is untouched). **Any future action on this abstract `orderAction` element (e.g. `ArchiveOrders`) will need the same raw-SOAP treatment**, not the generated port method.

### Agentforce registration status (manual UI step still pending)
Per the established pattern (see §4/earlier session), a new `@InvocableMethod` must be registered as a real Agentforce action via Setup → Agentforce Studio → Agentforce Asset Library → Actions tab → "New Agent Action" before it is actually callable by an agent — deploying the Apex class alone is not enough. **`Push_Order_to_Google_Ad_Manager` and `Delete_Order_From_Google_Ad_Manager` are NOT yet registered this way** — `agentscript.txt` and the deployed `.agent` bundle already describe them (validated via `sf agent validate authoring-bundle`, success), but the user still needs to create both actions in the UI against `GAMOrderPushService`/`GAMOrderDeleteService`, matching the `source`/`target` names already in `agentscript.txt`. Note `lineItemsPushed` was deliberately typed `Decimal` (not `Integer`) in `GAMOrderPushService.OrderPushResult`, working around the known Agent Action Wizard bug with Integer-typed outputs — do not change it back to `Integer`.

### Standing regression check (run after any change touching shared Apex)
`test_gam_still_works.apex` (calls `GAMNetworkServiceClient.getCurrentNetwork()`) — re-run and confirmed passing after every change in this section. This is the user's explicit standing instruction: never let GAM auth or the Optimization Agent break while building new features.

### Not yet built (unchanged from §10, restated for a fresh session)
Email-to-Case/Web-to-Case intake, real pre-sale Forecast/Availability check against GAM, inventory allocation splits, two-way sync back into Salesforce, a formal Salesforce Approval Process for Quotes (currently a manual status-field edit). Also still open: the `Optimization_Change_Log__c`/`Optimization_Change_Request__c` "zero new custom objects" architecture conflict (§10-adjacent, flagged but not resolved), and `CampaignSuggestionApplicationService`'s separate Account/Opportunity/Quote chain duplicating `CampaignIdentityResolutionService`/`CampaignMediaPlanService`.

### Immediate next steps (supersedes §12 items 1-2, which are stale/likely already resolved — verify before resuming them)
1. Decide on the "zero new custom objects" conflict for `Optimization_Change_Log__c`/`Optimization_Change_Request__c` — refactor onto standard objects, or get an explicit exception from the Salesforce solution architects.
2. Real Ad Unit/creative-size mapping for `GAMOrderPushService` (currently MVP placeholders, see above).
3. Pre-sale availability/forecast check against GAM before an Order is created.
4. Verify whether §12 items 1-3 (GAM onboarding hosting decision, Phase 2 auto-provisioning) are still open or were completed in a session not reflected in this file — re-read §7 before assuming either way.
5. Optionally still register `Push_Order_to_Google_Ad_Manager`/`Delete_Order_From_Google_Ad_Manager` in Agentforce Asset Library UI if conversational (not just record-page-button) access is wanted later — lower priority now that §14's record page button covers the practical need.

---

## 14. Order Push/Delete Record Page Button + Real Quote Approval Process (new session, fully built and verified live)

### GAM Order Push/Delete via a Lightning button on the Order record page (bypasses Agentforce entirely)
Rather than fight Agentforce's action-publish pipeline further, built a direct UI path:
- **`GAMOrderButtonController.cls`** (`@AuraEnabled`) wraps `GAMOrderPushService`/`GAMOrderDeleteService` and a status-check method (`getGamOrderStatus`, keyed off `AdOrderItem.AdServerOrderIdentifier`).
- **`gamOrderAction` LWC** — dropped onto the Order Lightning Record Page. Shows "Push to Google Ad Manager" or "Delete from Google Ad Manager" depending on real status, with a confirmation modal before either irreversible action.
- **Critical gotcha found and fixed**: `GAMOrderPushService.OrderPushResult`/`GAMOrderDeleteService.OrderDeleteResult` only mark fields `@InvocableVariable` (for Flow/Agentforce), not `@AuraEnabled` - Lightning silently strips every field from an `@AuraEnabled` method's return value unless each field is itself `@AuraEnabled`, so the browser always received `{}` regardless of what Apex actually did (this caused several confusing "Push/Delete Failed" toasts on calls that had, in fact, succeeded). Fixed by mapping into local `GamPushResult`/`GamDeleteResult` DTOs inside the controller, without touching the already-verified push/delete services.
- **Made push idempotent and safe org-wide**: `createGamLineItems` now finds-or-creates by name (matching the existing Order-level logic) instead of blindly creating, and duplicate product names within one Order (confirmed real case: Order 00000106 has "Conflict Zone" x3) are auto-disambiguated ("Conflict Zone (2)", "(3)") since GAM requires unique Line Item names within an Order. Also auto-creates a missing `AdOrderItem` record when one doesn't already exist (some Orders in this org never had one).
- **Delete now clears the Salesforce-side fields on success**: originally `GAMOrderDeleteService` deleted the real GAM Order but left `AdOrderItem.AdServerOrderIdentifier`/`AdServerOrderLineIdentifier` populated, so the button kept showing "Delete" after a successful delete. Fixed to null both fields on success.
- **A separate, real external-state finding, not a bug**: one Order's GAM Order (4207502064) was confirmed genuinely gone from GAM's own order list despite Salesforce believing it existed - GAM itself is not perfectly consistent with a Salesforce-side cache; fixed by re-pushing (which creates a fresh, real Order) rather than trying to force-delete something that no longer exists.

### Real Salesforce Approval Process for Quotes (replaces the manual status-field edit)
- **`force-app/main/default/approvalProcesses/Quote.Media_Plan_Approval.approvalProcess-meta.xml`** - single-step approval process on the standard `Quote` object. Entry criteria: `Status = 'Needs Review'`. Approver: Mohammed Raqib (user choice made explicitly this session - single-user demo org, not a role-hierarchy manager lookup, which isn't set up here).
- **`force-app/main/default/workflows/Quote.workflow-meta.xml`** - two field updates used as the approval/rejection actions: `Approve_Media_Plan_Quote` (Status -> 'Approved'), `Reject_Media_Plan_Quote` (Status -> 'Rejected').
- Verified live end to end via `Approval.process()`: set a real Quote to 'Needs Review' -> submitted -> assigned to the designated approver -> approved -> Status auto-flipped to 'Approved'. `CampaignOrderConversionService`'s existing "Approved/Accepted" gate (§ Campaign_Planner in `agentscript.txt`) needed no changes - it already checked `Quote.Status`, which this process now sets for real instead of a human editing the field directly.
- **Done**: "Submit for Approval" was added to the Quote Lightning Record Page's Highlights Panel actions (it was already on the page layout's action list, just not surfaced on the Highlights Panel). Verified live through the actual UI, not just Apex: Draft -> Needs Review -> Submit for Approval -> routed to the approver -> Approved in the approver's queue -> Status auto-flipped to 'Approved'.

---

## 15. "Zero New Custom Objects" Conflict Resolved - Optimization Audit Log/Change Requests Moved onto Case (new session)

**Decision made explicitly by the user**: refactor onto standard objects rather than keep the custom objects or do a hybrid. This closes out the architecture conflict flagged since the first handoff.

### What changed
- `Optimization_Change_Log__c` and `Optimization_Change_Request__c` (custom objects) are **deleted from the org**. Both are gone from `force-app/main/default/objects/` too.
- Both are replaced by the standard **`Case`** object (NOT `Task` - see gotcha below), using the default/Master record type. Six new custom **fields** on Case (custom fields are fine under the rule; only new custom objects were banned):
  - `Optimization_Line_Item_Id__c`, `Optimization_Advertiser__c` (Text)
  - `Optimization_Event_Type__c` (Picklist, backed by the new `Optimization_Event_Type` Global Value Set) - populated for audit log entries (SCHEDULED_EVALUATION, GAM_ORDER_PUSHED, etc.)
  - `Optimization_Action_Type__c` (Picklist, backed by the new `Optimization_Action_Type` Global Value Set) - populated for change requests (INCREASE_DAILY_PACING, etc.)
  - `Optimization_Current_Pacing_Percentage__c`, `Optimization_Pacing_Adjustment_Pct__c` (Number)
  - `Optimization_Health__c` (Text)
  - Standard Case fields reused: `Subject` (short label), `Description` (details/reasoning, prefixed with `[Actor: <name>]` for push/delete logs since there's no dedicated Actor field), `Status` (holds `Closed` for log entries, `Pending Approval`/`Approved`/`Rejected`/`Applied` for change requests - Case's Status picklist is unrestricted, so these values work without needing to touch the org-wide Status picklist).
- A Case with `Optimization_Event_Type__c` populated = a log entry (write-only, matches old behavior - nothing reads these back). A Case with `Optimization_Action_Type__c` populated = a change request (the scheduler dedupes on `Status = 'Pending Approval'`, same as before).
- Updated: `OptimizationEvaluationBatch.cls` (the scheduler - the exact class the user repeatedly said must not break), `GAMOrderPushService.cls`, `GAMOrderDeleteService.cls`, and the `Optimization_Agent_Access` permission set's field permissions. Comment-only references in `OptimizationDecisionEngine.cls`/`OptimizationSchedulerJob.cls` updated too.
- **Historical data (59 log rows + 4 change request rows) was NOT migrated** - a genuine, unexplained org-side issue made the old objects' field values briefly unreadable via every API path (SOQL, Apex, REST describe) right when migration was attempted, despite Tooling API still listing the fields as existing. The user explicitly chose to delete the objects anyway rather than block on it (low-value historical audit data). If this exact symptom (fields existing in Tooling API metadata but rejected everywhere else with "No such column", unrelated to anything just deployed) recurs, it's worth escalating to Salesforce support - it was never fully explained.

### Critical gotcha: Task was the first choice and does NOT work in this org
Custom fields could not be added to the standard `Task` object at all - not via Metadata API deploy (failed with a misleading cascading `"bad value for restricted picklist field: Task"` error on every field, even a single plain Text field with no picklist involved) and confirmed via Setup UI too (Object Manager -> Task -> Fields & Relationships has **no "New" button** at all). This is almost certainly a Media Cloud/managed-package restriction on the Activity model in this org. **Do not attempt to add custom fields to Task in this org again** - use Case (or another standard object confirmed to accept new fields, like Case was here) instead.

### Safety check performed before using Case
`Case` already has a "Campaign Request" record type wired to the protected intake pipeline (`CampaignCaseTrigger`/`CampaignCaseTriggerHandler`, §13). Confirmed the trigger handler explicitly checks `newCase.RecordTypeId != campaignRequestRtId` and no-ops otherwise - so these new optimization-audit Cases (created with the default/Master record type, RecordTypeId left unset) never touch that logic. Verified live: pushing/deleting a GAM order and running the scheduler both create real Cases, and the trigger fires (as it does for any Case) but correctly does nothing.

### Verified live after the full refactor
- `OptimizationEvaluationBatch` run via `Database.executeBatch()`: completed 0 errors, 15/15 chunks, created real `SCHEDULED_EVALUATION` log Cases and one real `INCREASE_DAILY_PACING` change request Case in `Pending Approval`.
- `GAMOrderPushService`/`GAMOrderDeleteService` push and delete both verified against a real GAM order, each producing the correct `Case`-based audit log entry (`GAM_ORDER_PUSHED`, `GAM_ORDER_DELETED`).
- Standing `test_gam_still_works.apex` regression check passed after every step.

### Also encountered (worth remembering for future deploys)
An org-wide Apex schema-cache propagation delay occurred after the Case field deploys - briefly, even Apex compilation rejected the OLD (unrelated, pre-existing) custom object fields with "No such column" errors, not just the newly deployed ones. This resolved on its own after several minutes. If a deploy of new fields/objects causes seemingly unrelated existing schema to become briefly unqueryable, this is likely the same phenomenon - wait a few minutes and retry before assuming something is broken.

---

## 16. Real Ad Unit / Creative-Size Mapping for GAMOrderPushService (new session)

Replaces the previous hardcoded "first ACTIVE Ad Unit in the network" / fixed 300x250 creative size.

### What changed
- Three new fields on **`Product2`**: `GAM_Ad_Unit_Name__c` (Text - exact GAM Ad Unit name to target), `GAM_Creative_Width__c`, `GAM_Creative_Height__c` (Number, pixels). All optional.
- `GAMOrderPushService.push()` now resolves, per OrderItem, the GAM Ad Unit by looking up `Product2.GAM_Ad_Unit_Name__c` against GAM (`findAdUnitIdByName`, new helper) when a product has one configured. Falls back to the existing "first ACTIVE Ad Unit in the network" behavior when a product has no Ad Unit configured, or the configured name isn't found/isn't ACTIVE in GAM - never throws for a bad/renamed name, degrades gracefully instead. Ad Unit lookups are cached per-name within one push call to avoid redundant callouts when multiple line items share a configured Ad Unit.
- Creative size (`CreativePlaceholder.size`) now comes from `Product2.GAM_Creative_Width__c`/`GAM_Creative_Height__c` when set, defaulting to 300x250 otherwise.
- **Honest limitation, unchanged**: there is still no real `AdSpaceSpecification`-driven targeting model in this project - this is a per-product config field an admin fills in, not an automatic mapping engine. There was no natural key to auto-derive one: GAM's 520 real Ad Units in this network are generic news-website sections (from earlier onboarding/testing) with zero naming relationship to this org's actual product catalog (Digital Banner, Local Radio, National TV, etc.).

### A real gotcha hit while building this (distinct from the schema-cache delay above)
New fields can appear to fail with **"No such column"** in Apex/REST/CLI even well after the schema-cache delay has cleared - in this case the real cause was **Field-Level Security**, not propagation: newly deployed custom fields are not automatically visible to the running user's profile just because they deployed successfully, and Salesforce disguises an FLS-denied field as "No such column" rather than a permissions error (for both SOQL and DML). Fix: add an explicit `fieldPermissions` entry for the new field to a permission set already assigned to the user (done here via `Optimization_Agent_Access`) and redeploy - it worked immediately after that, ruling out any remaining propagation-delay question. **When a brand-new field says "No such column" and waiting doesn't fix it, check FLS before assuming it's the propagation-delay phenomenon again.**

### Verified live
Configured a real product (`Digital Audio`) with `GAM_Ad_Unit_Name__c = 'AllNews_Homepage_Display_Leaderboard_1'`, width 728, height 90. Pushed a fresh GAM Order and confirmed via a direct `getLineItemsByStatement` query against the real created Line Item: `CREATIVE_SIZE: 728x90` (not the 300x250 fallback) and `TARGETED_AD_UNIT_ID: 23204757459` (the exact configured Ad Unit, not the fallback `23200882692`). Test order cleaned up (deleted from GAM) afterward. Standing `test_gam_still_works.apex` regression check passed.

---

## 17. Pre-Sale GAM Availability Check (new session) - built and deployed, blocked from full live verification by a real GAM network limitation, not a code defect

### What was built
- **`GAMForecastServiceStub.cls`** - sixth WSDL2Apex-generated GAM SOAP stub (Company/Order/LineItem/User/Inventory/**Forecast**), same generation process as the others (Setup -> Generate from WSDL, manual copy-paste, `ApplicationException`/`ApiException` rename). Hit the exact same non-flattened-inheritance bug as before: `LineItem` only had 2 of its ~64 real fields (`targeting`, `creativeTargetings`) - `LineItemSummary`'s 62 base fields were missing entirely, including their individual `_type_info` declarations (a subtlety worth remembering: merging just the public fields without also merging each field's own `<field>_type_info` array causes a different, harder-to-diagnose runtime error - `System.CalloutException: Unable to find typeInfo for field X` - rather than a compile error, since Apex compiles fine but the SOAP serializer can't map the field at actual callout time).
- **`GAMAvailabilityCheckService.cls`** (new, `@InvocableMethod`, read-only, no `isConfirmationRequired` needed since it makes zero external writes - matches the Forecast/Optimization read-only action pattern already established) - `checkAvailability(quoteId)`. For every `AdQuoteLine` on a Quote's media plan, builds a `ProspectiveLineItem` (never saved to GAM) using the same per-product Ad Unit/creative-size resolution as `GAMOrderPushService` (§16), calls `ForecastService.getAvailabilityForecast`, and returns per-line `requestedUnits`/`availableUnits`/`possibleUnits`/`matchedUnits` plus a deterministic `FULLY_AVAILABLE`/`PARTIALLY_AVAILABLE`/`UNAVAILABLE` classification - Apex computes the comparison, it does not recommend anything, same architecture principle as everywhere else in this project.
- Two more real GAM SOAP quirks hit and fixed along the way:
  - `getAvailabilityForecast`'s second parameter (`AvailabilityForecastOptions`) must be a real (even empty) object, not `null`, or GAM rejects the whole request with `NotNullError.ARG2_NULL`.
  - GAM's forecast `startDateTimeType` needs to be `'IMMEDIATELY'` (matching the working pattern already used in `GAMOrderPushService`) rather than an explicit `startDateTime`/`'USE_START_DATE_TIME'` - an explicit start date computed as "today at midnight" can still be rejected as `LineItemFlightDateError.START_DATE_TIME_IS_IN_PAST` depending on the org's local timezone vs GAM's clock.

### Genuinely blocked on: this GAM network has no forecast data yet
Every single call - across two different real, live media plans and multiple different real Ad Units (including a completely generic, parameter-minimal direct test unrelated to any Salesforce data) - returns the same real GAM SOAP fault: **`ForecastingError.NO_FORECAST_YET`**. This was proven to be a network-wide condition, not specific to any one Ad Unit, Quote, or code path: a bare-minimum standalone test hitting the network's very first Ad Unit with no real-world parameters hit the identical error. GAM's `ForecastService` requires its own internal forecasting job to have run against real historical traffic for a network before `getAvailabilityForecast` can return real numbers - this test/sandbox network (code `23201882692`) evidently has not accumulated enough real traffic/history for GAM to have computed one yet. **This cannot be fixed from the Salesforce side** - it would need either time (if this network does eventually get real traffic and GAM's forecasting job catches up) or testing against a different GAM network that already has an established forecast.

### What this means for now
The code is real, deployed, and calling GAM correctly - verified by the fact that it's receiving genuine, specific GAM business-logic errors (not connection/auth/schema errors) at every step, and each fix along the way was proven correct by moving to the *next*, different real GAM error. When this network (or a different one used for a real client) has forecast data available, this should work without further changes. Cannot be marked "verified live" in the same sense as the other GAM connectors in this project, since a genuine successful `AvailabilityForecast` response was never obtained - flagged here honestly rather than claimed as fully proven.

---

## 18. Email-to-Case Intake + Two-Way GAM Delivery Sync (new session, both verified live)

### Email-to-Case intake
- **`CampaignEmailIntakeHandler.cls`** (`global`, implements `Messaging.InboundEmailHandler`) - creates a real Case with the `Campaign_Request` record type from any inbound email, populating only what an email genuinely gives for free (`SuppliedEmail`, `SuppliedName`, `Subject`, `Description` from the raw body). **Deliberately does not attempt to parse structured fields** (advertiser name, budget, flight dates) out of free-form email text - that would mean guessing, which this project's architecture avoids. Instead it lets the existing `CampaignIntakeService`/`CampaignCaseTriggerHandler` pipeline run its normal deterministic validation and report "missing fields" back, which is exactly the scenario that reporting path already existed for.
- Verified live via a direct call simulating a real inbound email: created a real Case (`Campaign_Request` record type), correctly auto-flagged `Validation_Status__c = 'Incomplete'` by the existing pipeline (since the email had no budget/dates), with zero changes needed to `CampaignIntakeService` or the trigger.
- **The Email Service registration itself (Setup -> Email Services -> New Email Service, pointing at this class) could not be deployed via Metadata API** - `EmailServicesFunction`'s XML schema has strict, undocumented element ordering that repeated attempts couldn't satisfy blind. This is a genuine one-time manual Setup step the user needs to do (2 minutes): create the Email Service, generate an address, and that's it - the Apex logic behind it is already deployed and proven correct.
- **Not yet done**: the actual Setup UI registration (see above) - once done, get the generated email address and this channel is fully live.

### Two-way GAM delivery sync (separate from, and does not touch, the CSV-backed Optimization/Forecast pipeline)
- Four new fields on **`AdOrderItem`**: `GAM_Delivered_Impressions__c`, `GAM_Delivered_Clicks__c`, `GAM_Delivery_Status__c`, `GAM_Last_Synced__c`.
- **`GAMDeliverySyncBatch.cls`** (Batchable, scope 25) - for every `AdOrderItem` with a real `AdServerOrderLineIdentifier` (i.e. genuinely pushed to GAM), pulls real stats from `LineItemService.getLineItemsByStatement` (batching multiple GAM Line Item IDs into one `WHERE id IN (...)` PQL query per chunk instead of one callout per record) and writes delivered impressions/clicks/status back. Read-only against GAM.
- **`GAMDeliverySyncSchedulerJob.cls`** (Schedulable) - `scheduleHourly()` to turn it on, `runNow()` for on-demand runs. **Deliberately kept fully separate from `OptimizationSchedulerJob`/`OptimizationEvaluationBatch`** - the Optimization Agent's own evidence pipeline stays exactly as CSV-backed as it already was, per the standing instruction to never disturb that working pipeline. This sync only keeps `AdOrderItem`'s own fields current; it does not feed Forecast/Optimization at all.
- **Real gotcha hit and fixed**: Batch Apex only allows one callout per `execute()` unless the batch class also implements `Database.AllowsCallouts` - without it, the very first real callout failed with `System.AsyncException: Too many callouts: 1` (an easy one to miss since the code compiles and even runs its first chunk before failing).
- Verified live: ran `GAMDeliverySyncSchedulerJob.runNow()` against 12 real `AdOrderItem` records (Order 4207491057, still live in GAM from earlier testing) - completed 0 errors, and confirmed via direct query that `GAM_Delivery_Status__c` was correctly synced to the real value (`DRAFT`, since these test Line Items were never activated in GAM) with a real `GAM_Last_Synced__c` timestamp.
- Standing `test_gam_still_works.apex` regression check passed.

### Not attempted this session: inventory allocation splits (the whiteboard's GAM/FreeWheel/TC split)
Explicitly deprioritized per the user's own earlier instruction ("leave that tc bro") - the "TC" portion of that whiteboard concept was never actually defined, and building a real split-allocation engine against undefined requirements would mean guessing rather than building something real. Flagged here rather than silently skipped; needs the user to define what TC actually means and what the real split logic should be before this can be built honestly.

---

## 19. Optimization Agent: Crisp Responses + Amendment Quote Flow (requirement from the user's lead, new session)

Two changes requested together: (1) shorten the Optimization Agent's response, (2) change what happens when a suggestion is applied so it produces a real Amendment Quote tied to the advertiser's actual Order, with both the Quote and Order links surfaced.

### 1. Crisp responses
Rewrote the `Campaign_Optimization` subagent's reasoning instructions in `agentscript.txt` (and the mirrored `.agent` bundle) - replaced the old multi-section report (Optimization Summary / Performance vs Portfolio Benchmark / Current Targeting Configuration / Evidence-Based Signals / Candidate Alternatives / Contention Context / Data Quality Notes / Recommended Next Steps, each its own headed block) with a fixed 4-line format:
1. One line: Line Item, Advertiser, Health, Urgency.
2. One or two sentences on the single biggest driver, not every metric.
3. A numbered list of 1-3 suggestions worth acting on (still numbered - the "apply suggestion N" reply flow depends on this).
4. One closing disclaimer line.
Follow-up detail (targeting, benchmarks, etc.) is now answered only if the user actually asks, instead of front-loaded into every response. Validated via `sf agent validate authoring-bundle` and deployed - **not yet re-tested with a live agent conversation this session**, worth a quick live check before calling this fully proven.

### 2. Amendment Quote flow (`CampaignSuggestionApplicationService.apply()`)
When a human confirms an optimization suggestion, the resulting Quote now depends on whether a real Order already exists for that advertiser (`SELECT ... FROM Order WHERE AccountId = :advertiserAccount.Id ORDER BY CreatedDate DESC LIMIT 1`):
- **If an Order exists** - creates an **Amendment Quote**: carries forward the Order's current real `OrderItem`s as `QuoteLineItem`s (copied as-is), plus the newly confirmed suggestion's own line, so the Quote represents the *full* updated plan, not just the isolated change. Sets `Quote.Status = 'Needs Review'` so it's one click from entering the real `Quote.Media_Plan_Approval` process built earlier this session (§14) - the client-approval step the user described.
- **If no Order exists yet** - falls back to the original behavior (standalone Draft Quote for just the suggestion).
- The result's `explanation` field (already a registered Agentforce output - no new action re-registration needed) now always states which of the two happened and includes **both real record links** (`URL.getOrgDomainUrl()...`/recordId) - the new Quote's, and the existing Order's when amending.
- Verified live via direct Apex calls: (a) against Nike, which has a real Order (00000108, 2 real OrderItems) - produced a real Amendment Quote with 3 QuoteLineItems (2 carried forward + 1 new), Status `Needs Review`, explanation containing both real links; (b) against a brand-new advertiser with no Order - correctly fell back to a standalone Draft Quote with one link, explanation stating no Order was found. Test Account/Opportunity/Quote from the fallback test were deleted afterward as throwaway data.
- Standing `test_gam_still_works.apex` regression check passed.

### 3. Apply the approved amendment to the live Order + push to GAM (closes the loop, same-session follow-up)
The gap flagged above got closed the same session, per the user's explicit description of the full intended flow (client approves the Amendment Quote -> changes get applied to the Order -> pushed to GAM).

- New field **`Quote.Amends_Order__c`** (Lookup to Order) - set automatically by `CampaignSuggestionApplicationService` whenever it creates an Amendment Quote, so the Order it amends is unambiguous later (not re-derived by "most recent Order for this Account," which could pick the wrong one if more Orders exist by the time of approval).
- New class **`CampaignAmendmentApplicationService.cls`** (`@InvocableMethod applyApprovedAmendment`) - given an approved (`Approved`/`Accepted`) Amendment Quote:
  1. Verifies it's actually approved and actually an amendment (`Amends_Order__c` populated) - refuses otherwise with a clear message.
  2. **Syncs the real Order's `OrderItem`s to match the approved Quote's `QuoteLineItem`s exactly** (matched by Product2Id): products on both get their Quantity/UnitPrice updated to the Quote's values (this is how an underperforming line gets genuinely overruled - the human edits/removes it on the Quote before approving, and that becomes the new Order state), products only on the Quote get inserted, products only on the Order (no longer on the approved Quote) get deleted.
  3. Enqueues a **`Queueable`** (`AmendmentPushQueueable`, inner class) to push the now-updated Order to GAM via the existing `GAMOrderPushService.push()` - required because the OrderItem sync is DML, and Salesforce forbids a callout in the same transaction right after DML ("You have uncommitted work pending" - hit and fixed this exact error during testing). The push's real outcome still lands in the Case-based audit trail (`GAM_ORDER_PUSHED`/`GAM_ORDER_PUSH_FAILED`) moments later, even though the method itself returns before the push completes.
- **`GAMOrderPushService.createGamLineItems` was also upgraded**: previously, if a same-named Line Item already existed in GAM, it was left completely untouched (pure find, no update) - meaning a re-push after an approved amendment would silently NOT reflect the new pacing/budget/end-date in GAM. Now it calls `LineItemService.updateLineItems` on any existing match with the new goal/cost/end-date, so a re-push genuinely carries the approved change through to the real ad server.
- New Agentforce action **`Apply_Approved_Amendment_to_Order`** wired into the `Campaign_Optimization` subagent in `agentscript.txt` (confirmation-gated, real/live/irreversible). Registered in Agentforce Asset Library by the user this session.
- **Verified live via direct Apex, full loop, real data**: created a fresh Amendment Quote for Nike -> submitted it through the real `Quote.Media_Plan_Approval` process -> approved it -> called `applyApprovedAmendment` -> Order 00000108's `OrderItem`s were synced to the approved Quote's lines -> the queued push succeeded against real GAM (Order 4206270443, 2 real Line Items). One real, unrelated data issue was found and fixed along the way: Nike's test Order had a stale `EffectiveDate` (from much earlier this session) whose implied end date had since passed, correctly triggering a real GAM `LineItemFlightDateError` - fixed by setting a real future `EndDate`, not a code change.

### 4. Real root-router misrouting found live - fixed with an Apex-level guard, not just prompt wording
Live conversational testing (`sf agent preview send`) with phrasing like "the optimization Amendment Quote for Nike has been approved, apply the amendment and push it to GAM" **consistently routed to `Campaign_Planner`'s `Convert_Approved_Media_Plan_to_Order`** instead of `Campaign_Optimization`'s new `Apply_Approved_Amendment_to_Order` - even after adding an explicit routing rule to the root agent's instructions naming "amendment" phrasing. This actually created a real, unwanted duplicate Order (`801dN0000131pHeQAI`) on the first confirmed test before being caught and deleted - the root router (`sfdc_ai__DefaultEinsteinHyperClassifier`) appears to weight "approved" + "order" language toward the Campaign_Planner action regardless of "amendment"/"optimization" wording added to its own instructions, a real platform routing limitation, not something further prompt tweaking reliably fixed in testing.

**Real fix applied (defense in depth, not just documentation)**: added a hard guard directly in `CampaignOrderConversionService.cls` - if the Quote being converted has `Amends_Order__c` populated, it refuses with a clear message directing to `Apply_Approved_Amendment_to_Order` instead of the duplicate Order it would otherwise create. This makes the misrouting **safe** even though it isn't fully eliminated: re-tested the identical conversation afterward and confirmed live - the agent still initially picked the wrong action, but Apex refused cleanly, no duplicate Order was created, and the agent relayed the correct next step to the user on its own. **Root-cause routing accuracy for this specific "amendment" scenario remains an open, real limitation** - worth revisiting if it recurs, but no longer risks bad data in the meantime.
- Standing `test_gam_still_works.apex` regression check passed after this too.
