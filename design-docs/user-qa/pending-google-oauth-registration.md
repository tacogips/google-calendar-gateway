# Pending Google OAuth application registration

## User request

All Google gateway and Gmail commands should open the browser on `auth login`
and persist user credentials without requiring the end user to supply a
`google-client.json` file. A common Swift library is permitted.

## Required input

Which Google Cloud project should own the gateways' registered desktop OAuth
application? Alternatively, supply the location of an existing desktop client
registered for these gateways. Do not put secret values in this document.

## Why this is required

The application's registration identifies the application before the browser
flow can issue a user token. The source audit has not found a registered client
that can be distributed as the default for these gateways. Google Cloud's
`gcloud` client does not remove the custom client requirement for non-Cloud
scopes such as Drive. Project selection and app ownership cannot be inferred
from the GitHub organization name.

## Local discovery

The shared OAuth vault returns an empty client profile list. The installed gcloud
581.0.0 CLI has `ai-tools-proj` selected as its default project. This is a candidate
for registration; the project has not been chosen explicitly for distributing
these gateways' OAuth app. No application or consent configuration has been
created or modified.

## Work already independent of registration

- Calendar reader/writer split, Google-only branding and repository rename.
- Browser loopback authorizer and login orchestration exposed in `GoogleServiceGatewayCore`.
- Shared login rejects incomplete grants and bounds incomplete HTTP callbacks by the login timeout.
- Analytics and Service `auth login` aliases.
- Calendar login default credential.

OCR interactive login and private token persistence are implemented and tested.
Marketing and Analytics now select implicit login profiles without config files.
All Service executable roles now route `auth login` through the shared adapter;
Gmail synthesizes role-appropriate default profiles, and the deprecated Docs
executable forwards to the Docs reader. The integration of a registered default
client and live browser authorization remain unfinished. See the implementation inventory in
`../specs/google-auth-consistency.md`.

## Registration dependency rechecked on 2026-09-30

The installed gcloud 581.0.0 binary still reports `ai-tools-proj` as the selected
project. This confirms the local setting, not ownership of a gateway OAuth
application. The project selection request remains unanswered.

Google's [native application OAuth documentation](https://developers.google.com/identity/protocols/oauth2/native-app)
requires an application client registration before sending the browser
authorization request. No default client has been selected for these gateways,
so clean login cannot yet reach Google account selection without an override.
