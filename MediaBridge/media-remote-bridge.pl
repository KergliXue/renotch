use strict;
use warnings;
use DynaLoader;

my $library = $ARGV[0] or die "缺少媒体桥接组件\n";
my $handle = DynaLoader::dl_load_file($library, 0x01)
    or die "无法加载媒体桥接组件\n";
my $symbol = DynaLoader::dl_find_symbol($handle, "renotch_media_remote_start")
    || DynaLoader::dl_find_symbol($handle, "renotch_qq_music_start")
    or die "媒体桥接组件不完整\n";
my $start = DynaLoader::dl_install_xsub("Renotch::MediaRemote::start", $symbol);
$start->();
