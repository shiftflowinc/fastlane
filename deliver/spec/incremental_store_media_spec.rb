require 'deliver/runner'
require 'tmpdir'

describe 'Incremental store media' do
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

  def preview_sync(remote, contents)
    directory = File.join(@directory, 'en-US')
    FileUtils.mkdir_p(directory)
    contents.each { |name, bytes| File.binwrite(File.join(directory, name), bytes) }
    allow(FastlaneCore::VideoUtils).to receive(:read_video_duration_seconds).and_return(20)
    allow(FastlaneCore::VideoUtils).to receive(:read_video_resolution).and_return([886, 1920])
    set = Spaceship::ConnectAPI::AppPreviewSet.new('set', { preview_type: 'IPHONE_67', app_previews: remote })
    locale = double('locale', locale: 'en-US', get_app_preview_sets: [set])
    other = double('unselected locale', locale: 'fr-FR')
    expect(other).not_to receive(:get_app_preview_sets)
    version = double('version', get_app_store_version_localizations: [locale, other])
    app = double('app', get_edit_app_store_version: version)
    sync = Deliver::SyncAppPreviews.new(app: app, platform: 'IOS', app_previews_path: @directory, sync_app_previews: true, wait_for_processing: false)
    yield(set)
    sync.sync_from_path
  end

  def preview(id, name, bytes)
    Spaceship::ConnectAPI::AppPreview.new(id, { file_name: name, source_file_checksum: bytes && Digest::MD5.hexdigest(bytes) })
  end

  it 'keeps unchanged previews and replaces only changed previews' do
    kept = preview('kept', '01_IPHONE_67.mp4', 'same')
    old = preview('old', '02_IPHONE_67.mp4', 'old')
    fresh = preview('new', '02_IPHONE_67.mp4', 'changed')
    expect(kept).not_to receive(:delete!)
    expect(old).to receive(:delete!)
    preview_sync([kept, old], { kept.file_name => 'same', old.file_name => 'changed' }) do |set|
      expect(set).to receive(:upload_preview).once.with(path: File.join(@directory, 'en-US', old.file_name), frame_time_code: nil, wait_for_processing: false) { set.app_previews = [fresh, kept] }
      expect(set).to receive(:reorder_previews).with(app_preview_ids: %w[kept new])
    end
  end

  it 'leaves a matching preview entirely unchanged' do
    kept = preview('kept', '01_IPHONE_67.mp4', 'same')
    expect(kept).not_to receive(:delete!)
    preview_sync([kept], { kept.file_name => 'same' }) do |set|
      expect(set).not_to receive(:upload_preview)
      expect(set).not_to receive(:reorder_previews)
    end
  end

  it 'refuses unknown preview checksums before any deletion' do
    pending = preview('pending', '01_IPHONE_67.mp4', nil)
    expect(pending).not_to receive(:delete!)
    expect do
      preview_sync([pending], { pending.file_name => 'same' }) { |set| expect(set).not_to receive(:upload_preview) }
    end.to raise_error(/pending.*checksum/)
  end

  it 'rejects combining preview sync with full overwrite' do
    expect do
      Deliver::SyncAppPreviews.new(app: nil, platform: 'IOS', app_previews_path: @directory, sync_app_previews: true, overwrite_preview_videos: true)
    end.to raise_error(/sync_app_previews.*overwrite_preview_videos/)
  end

  it 'refuses invalid local videos before deleting a remote preview' do
    kept = preview('kept', '01_IPHONE_67.mp4', 'same')
    expect(kept).not_to receive(:delete!)
    expect do
      preview_sync([kept], { kept.file_name => 'changed' }) do |set|
        allow(FastlaneCore::VideoUtils).to receive(:read_video_duration_seconds).and_return(5)
        expect(set).not_to receive(:upload_preview)
      end
    end.to raise_error(/local videos are invalid/)
  end

  it 'refuses more than three previews before making changes' do
    kept = preview('kept', '01_IPHONE_67.mp4', 'same')
    expect(kept).not_to receive(:delete!)
    contents = (1..4).to_h { |index| ["0#{index}_IPHONE_67.mp4", 'new'] }
    expect do
      preview_sync([kept], contents) { |set| expect(set).not_to receive(:upload_preview) }
    end.to raise_error(/limit is 3/)
  end

  it 'removes an obsolete preview without reuploading the retained preview' do
    kept = preview('kept', '01_IPHONE_67.mp4', 'same')
    removed = preview('removed', '02_IPHONE_67.mp4', 'obsolete')
    expect(kept).not_to receive(:delete!)
    preview_sync([kept, removed], { kept.file_name => 'same' }) do |set|
      expect(removed).to receive(:delete!) { set.app_previews = [kept] }
      expect(set).not_to receive(:upload_preview)
      expect(set).not_to receive(:reorder_previews)
    end
  end
end
