# ShiftFlow fork of fastlane

This fork exists so ShiftFlow can upload App Store creative assets (the iOS 27 product page header and the search results image) before upstream fastlane releases that feature, and finish screenshot and App Preview uploads without waiting for Apple processing. Flowfront pins its `Gemfile` to a commit on the `shiftflow/creative-assets` branch.

## What the branch carries

The `shiftflow/creative-assets` branch is the released tag `2.241.2` plus the three commits of [fastlane/fastlane#30442](https://github.com/fastlane/fastlane/pull/30442) by Hirokazu Tanaka (techiro), cherry-picked unchanged with their original author:

| Upstream PR commit | Subject |
| --- | --- |
| `87c4894d6` | support App Store creative image placements |
| `6af3a362d` | address creative asset review feedback |
| `75aae1176` | Harden creative asset retries and replacement failures |

The PR adds the `creative_assets` and `overwrite_creative_assets` options to _deliver_ and the spaceship models for Apple's App Asset Library. The tracking issue is [fastlane/fastlane#30461](https://github.com/fastlane/fastlane/issues/30461).

The PR's focused specs pass on this branch:

```sh
bundle exec rspec deliver/spec/upload_creative_assets_spec.rb deliver/spec/runner_spec.rb \
  spaceship/spec/connect_api/app_asset_library_spec.rb spaceship/spec/connect_api/asset_request_retry_spec.rb \
  spaceship/spec/client_spec.rb
```

Live placement creation against App Store Connect was not exercised by the PR author. Treat the first real upload as the first live test.

## Upload acceptance without processing waits

_deliver_ supports `skip_waiting_for_screenshot_processing: true` and `skip_waiting_for_app_preview_processing: true`. Both default to `false`. These modes finish after the upload requests succeed and filename ordering is applied. Transfer errors still fail; screenshots do not poll or retry processing. Preview uploads require all requested locales to exist, and do not select a still frame because that requires completed video processing. Check processing and preview still frames in App Store Connect before submission.

Creative assets retain their bounded image-readiness check: header placement requires the processed image specification, and old placements are preserved until every replacement image is ready.

## When to drop this fork

Drop the fork once a fastlane release includes fastlane/fastlane#30442 and equivalent screenshot/preview upload-acceptance options. Point Flowfront back at the released gem (`gem "fastlane", "~> 2.241"` or the release that contains the feature), then archive or delete this repository.

To move to a newer fastlane release before then, cut a new branch from that release tag, carry the creative-assets and upload-processing changes, rerun their focused specs and the repository checks, and update the pinned SHA in Flowfront.
