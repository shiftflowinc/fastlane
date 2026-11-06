# ShiftFlow fork of fastlane

This fork exists so ShiftFlow can upload App Store creative assets (the iOS 27 product page header and the search results image) before upstream fastlane releases that feature. Flowfront pins its `Gemfile` to a commit on the `shiftflow/creative-assets` branch.

## What the branch carries

The `shiftflow/creative-assets` branch is the released tag `2.241.2` plus the three commits of [fastlane/fastlane#30442](https://github.com/fastlane/fastlane/pull/30442) by Hirokazu Tanaka (techiro), cherry-picked unchanged with their original author:

| Upstream PR commit | Subject |
| --- | --- |
| `87c4894d6` | support App Store creative image placements |
| `6af3a362d` | address creative asset review feedback |
| `75aae1176` | Harden creative asset retries and replacement failures |

The PR adds the `creative_assets` and `overwrite_creative_assets` options to `deliver` and the spaceship models for Apple's App Asset Library. The tracking issue is [fastlane/fastlane#30461](https://github.com/fastlane/fastlane/issues/30461).

The PR's focused specs pass on this branch:

```sh
bundle exec rspec deliver/spec/upload_creative_assets_spec.rb deliver/spec/runner_spec.rb \
  spaceship/spec/connect_api/app_asset_library_spec.rb spaceship/spec/connect_api/asset_request_retry_spec.rb \
  spaceship/spec/client_spec.rb
```

Live placement creation against App Store Connect was not exercised by the PR author. Treat the first real upload as the first live test.

## When to drop this fork

Drop the fork once fastlane/fastlane#30442 ships in a fastlane release. Point Flowfront back at the released gem (`gem "fastlane", "~> 2.241"` or the release that contains the feature), then archive or delete this repository.

To move to a newer fastlane release before then, cut a new branch from that release tag, cherry-pick the same three commits, rerun the specs above, and update the pinned SHA in Flowfront.
