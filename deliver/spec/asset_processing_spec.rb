require 'spec_helper'
require 'deliver/upload_screenshots'
require 'deliver/sync_app_previews'

describe 'Store asset uploads without processing waits' do
  describe 'screenshots' do
    let(:uploader) { Deliver::UploadScreenshots.new }
    let(:display_type) { Spaceship::ConnectAPI::AppScreenshotSet::DisplayType::APP_IPHONE_55 }
    let(:remote_screenshots) do
      %w[2 1].map { |id| double('Screenshot', id: id, file_name: "#{id}.png", source_file_checksum: nil) }
    end
    let(:set) { double('ScreenshotSet', screenshot_display_type: display_type, app_screenshots: remote_screenshots) }
    let(:localization) { double('Localization', locale: 'en-US', get_app_screenshot_sets: [set]) }
    let(:screenshot) { double('LocalScreenshot', language: 'en-US', display_type: display_type, path: '/screenshot.png') }
    let(:version) { double('Version', version_string: '24.0.0', get_app_store_version_localizations: [localization]) }
    let(:options) { { platform: 'ios', screenshot_processing_timeout: 3600, skip_waiting_for_screenshot_processing: true } }

    before do
      Deliver.cache[:app] = double('App', get_edit_app_store_version: version)
      allow(Deliver::UploadScreenshots).to receive(:calculate_checksum).and_return('local-checksum')
      expect(uploader).not_to receive(:wait_for_complete)
      expect(uploader).not_to receive(:retry_upload_screenshots_if_needed)
    end

    it 'uploads and sorts screenshots whose processing checksums are still pending' do
      expect(set).to receive(:upload_screenshot).with(path: screenshot.path, wait_for_processing: false)
      expect(set).to receive(:reorder_screenshots).with(app_screenshot_ids: %w[1 2])
      uploader.upload(options, [screenshot])
    end

    it 'fails on transfer errors instead of reporting success or retrying' do
      expect(set).to receive(:upload_screenshot).once.and_raise('transfer rejected')
      expect(set).not_to receive(:reorder_screenshots)
      expect { uploader.upload(options, [screenshot]) }.to raise_error('transfer rejected')
    end
  end

  describe 'previews' do
    let(:app) { double('App') }
    let(:root) { Dir.mktmpdir('preview-processing-') }
    let(:preview_type) { Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPHONE_67 }
    let(:set) { double('PreviewSet', preview_type: preview_type, app_previews: []) }
    let(:localization) { double('Localization', locale: 'en-US', get_app_preview_sets: [set]) }
    let(:version) { double('Version', get_app_store_version_localizations: [localization]) }
    let(:sync) do
      Deliver::SyncAppPreviews.new(app: app, platform: 'IOS', app_previews_path: root,
                                  preview_frame_time_code: '00:00:05:00', wait_for_processing: false)
    end

    before do
      FileUtils.mkdir_p(File.join(root, 'en-US'))
      FileUtils.cp(File.join(__dir__, 'resources/app_previews/886x1920.mp4'), File.join(root, 'en-US/01_IPHONE_67.mp4'))
      allow(app).to receive(:get_edit_app_store_version).and_return(version)
    end

    after do
      FileUtils.remove_entry(root)
    end

    it 'disables processing and poster-frame selection while retaining filename order' do
      expect(set).to receive(:upload_preview).with(path: File.join(root, 'en-US/01_IPHONE_67.mp4'),
                                                 frame_time_code: nil, wait_for_processing: false) do
        allow(set).to receive(:app_previews).and_return([
                                                          double('Preview', id: '2', file_name: '02_IPHONE_67.mp4'),
                                                          double('Preview', id: '1', file_name: '01_IPHONE_67.mp4')
                                                        ])
      end
      expect(set).to receive(:reorder_previews).with(app_preview_ids: %w[1 2])
      sync.sync_from_path
    end

    it 'fails when a requested locale would otherwise be skipped' do
      allow(version).to receive(:get_app_store_version_localizations).and_return([])
      expect(set).not_to receive(:upload_preview)
      expect { sync.sync_from_path }.to raise_error(/App Preview locales are missing.*en-US/)
    end

    it 'still reports upload failures' do
      expect(set).to receive(:upload_preview).once.and_raise('transfer rejected')
      expect { sync.sync_from_path }.to raise_error(/1 App Preview upload error.*transfer rejected/)
    end
  end
end
