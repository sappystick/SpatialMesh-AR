Amplify backend scaffold for SpatialMesh-AR
=========================================

This folder contains a small scaffold to help create an Amplify REST API with Lambda handlers that match the app's expected endpoints:

- POST /spatial -> createSpatial (create spatial anchor)
- GET /spatial/{userId} -> getSpatial (list anchors for a user)
- GET /earnings/{userId} -> getEarnings (get user earnings)
- PUT /earnings -> putEarnings (update user earnings)

How to use
----------

1. From your project root run `amplify init` and choose the `spacialmesh-admin` profile when prompted. Suggested answers:

  ? Enter a name for the project: SpatialMeshAR
  ? Enter a name for the environment: dev
  ? Choose your default editor: (your editor)
  ? Choose the type of app that you're building: javascript
  ? What javascript framework are you using: none
  ? Source Directory Path: lib
  ? Distribution Directory Path: build
  ? Build Command: flutter pub get; flutter build apk
  ? Start Command: flutter run
  ? Do you want to use an AWS profile? Yes
  ? Please choose the profile you want to use: spacialmesh-admin

2. Add Auth (Cognito) if you want user sign-in:
  amplify add auth
  # Accept defaults or choose Email sign-in, etc.

3. Add a REST API (Amplify will create API Gateway + Lambda):
  amplify add api

  Use these answers when prompted:
  ? Please select from one of the below mentioned services: REST
  ? Provide a name for the API: SpatialMeshAPI
  ? Path: /spatial
  ? Choose a Lambda source: Create a new Lambda function
  ? Provide a name for the Lambda function: createSpatial
  ? Choose the runtime: NodeJS
  ? Do you want to configure advanced settings: No
  ? Do you want to edit the local lambda function now: No

  After adding the first route, add additional routes by running `amplify add api` again or editing the API in the Amplify Console:
  - Add GET /spatial/{userId} -> function name: getSpatial
  - Add GET /earnings/{userId} -> function name: getEarnings
  - Add PUT /earnings -> function name: putEarnings

4. Add storage for AR models (S3):
  amplify add storage
  # choose content (S3) and public/private as appropriate

5. Push the backend:
  amplify push

6. After `amplify push` completes, Amplify will create `amplify/` and generate the real `amplifyconfiguration.dart`. Replace the placeholder in `lib/amplifyconfiguration.dart` with the generated file.

Using the Lambda stubs
---------------------
The `functions` folder below includes example Lambda handlers you can paste into the functions Amplify creates. They are minimal and return dummy responses — replace the TODO areas with real DynamoDB/S3 logic.

Security note
-------------
- Do NOT commit AWS secrets or any produced credentials to the repo.
- Use the `spacialmesh-admin` profile configured locally.
