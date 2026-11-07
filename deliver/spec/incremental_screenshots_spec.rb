require 'deliver/runner'
require 'tmpdir'

describe 'Incremental screenshots' do
  around do |example|
    Dir.mktmpdir do |directory|
      @directory = directory
      FastlaneSpec::Env.with_env_values('FASTLANE_ENABLE_BETA_DELIVER_SYNC_SCREENSHOTS' => '1') { example.run }
    end
  end

  def screenshot(id, name, bytes, state = 'COMPLETE')
    Spaceship::ConnectAPI::AppScreenshot.new(id, {
      file_name: name, source_file_checksum: bytes && Digest::MD5.hexdigest(bytes), asset_delivery_state: { 'state' => state }
    })
  end

  def local_screenshot(name, bytes)
    path = File.join(@directory, name)
    File.binwrite(path, bytes)
    allow(Deliver::AppScreenshot).to receive(:calculate_display_type).with(path).and_return('APP_IPHONE_67')
    Deliver::AppScreenshot.new(path, 'en-US')
  end

  def screenshot_sync(local, remote)
    set = Spaceship::ConnectAPI::AppScreenshotSet.new('set', { screenshot_display_type: 'APP_IPHONE_67', app_screenshots: remote })
    locale = double('locale', locale: 'en-US', get_app_screenshot_sets: [set])
    other = double('unselected locale', locale: 'fr-FR')
    expect(other).not_to receive(:get_app_screenshot_sets)
    version = double('version', version_string: '24.0.0', get_app_store_version_localizations: [locale, other])
    app = double('app', get_edit_app_store_version: version)
    sync = Deliver::SyncScreenshots.new(app: app, platform: 'IOS', wait_for_processing: false)
    expect(sync).not_to receive(:wait_for_complete)
    yield(set)
    sync.sync(local)
  end

  it 'replaces one changed screenshot while retaining unchanged IDs and other locales' do
    local = [local_screenshot('0.png', 'same'), local_screenshot('1.png', 'changed')]
    kept = screenshot('kept', '0.png', 'same')
    old = screenshot('old', '1.png', 'old')
    replacement = screenshot('new', '1.png', 'changed')
    expect(kept).not_to receive(:delete!)
    expect(old).to receive(:delete!)
    screenshot_sync(local, [old, kept]) do |set|
      expect(set).to receive(:upload_screenshot).with(path: local.last.path, wait_for_processing: false) { set.app_screenshots = [replacement, kept] }
      expect(set).to receive(:reorder_screenshots).with(app_screenshot_ids: %w[kept new])
    end
  end

  it 'does not upload or delete unchanged screenshots' do
    local = [local_screenshot('0.png', 'same')]
    kept = screenshot('kept', '0.png', 'same')
    expect(kept).not_to receive(:delete!)
    screenshot_sync(local, [kept]) do |set|
      expect(set).not_to receive(:upload_screenshot)
      expect(set).not_to receive(:reorder_screenshots)
    end
  end

  it 'refuses unknown screenshot checksums before deleting or uploading anything' do
    local = [local_screenshot('0.png', 'changed')]
    pending = screenshot('pending', '0.png', nil, 'UPLOAD_COMPLETE')
    expect(pending).not_to receive(:delete!)
    expect do
      screenshot_sync(local, [pending]) { |set| expect(set).not_to receive(:upload_screenshot) }
    end.to raise_error(/pending.*checksum/)
  end

  it 'propagates an upload failure without retrying or replacing unrelated screenshots' do
    local = [local_screenshot('0.png', 'new')]
    expect do
      screenshot_sync(local, []) do |set|
        expect(set).to receive(:upload_screenshot).once.and_raise('transfer failed')
        expect(set).not_to receive(:reorder_screenshots)
      end
    end.to raise_error(/transfer failed/)
  end
end
