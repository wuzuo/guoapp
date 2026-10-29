import base64
import re
from dataclasses import dataclass
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]


def pubspec_version():
    text = (_ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
    match = re.search(r'^version:\s*([\w.+-]+)\s*$', text, re.MULTILINE)
    return match.group(1) if match else ''


@dataclass(frozen=True)
class BuildVariant:
    all_sources: bool = False

    @property
    def name(self):
        return '真果鉴' if self.all_sources else '红果鉴'

    @property
    def slug(self):
        return 'zhenguojian' if self.all_sources else 'hongguojian'

    @property
    def arguments(self):
        return ['--all-sources'] if self.all_sources else []

    @property
    def flutter_arguments(self):
        return ['--dart-define=ALL_SOURCES=' + str(self.all_sources).lower(),
                '--dart-define=APP_VERSION=' + pubspec_version()]

    @property
    def linker_flags(self):
        return '-s -w -X duanjuapp/native/core.buildAllSources=' + str(self.all_sources).lower()

    @classmethod
    def from_dart_defines(cls, encoded):
        values = {}
        for item in encoded.split(','):
            if not item:
                continue
            key, separator, value = base64.b64decode(item, validate=True).decode('utf-8').partition('=')
            if separator:
                values[key] = value
        return cls(values.get('ALL_SOURCES') == 'true')


def add_variant_argument(parser):
    parser.add_argument('--all-sources', action='store_true',
                        help='构建包含全部站源的真果鉴；默认构建仅红果的红果鉴')
