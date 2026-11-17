#!/bin/bash
# floppy new [--raw] [-l 라벨] 파일.img   1.44MB 이미지 생성 (기본: FAT12 포맷)
# floppy mount [--ro] 파일.img [디렉터리]  쓰기 가능 마운트 (기본 /mnt/floppy/<이름>)
# floppy umount 파일.img|디렉터리          sync 후 해제 + 마운트 디렉터리 삭제
set -u
SIZE=1474560
die(){ echo "오류: $*" >&2; exit 1; }
SU(){ if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }
mp_of(){ local b; b=$(basename "$1"); echo "/mnt/floppy/${b%.*}"; }
usage(){ sed -n '2,4p' "$0" | sed 's/^# //'; exit 1; }

new(){
  local raw=0 label="" f=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --raw) raw=1;;
      -l) shift; label="${1:-}";;
      *) [ -z "$f" ] && f="$1" || die "인자 과다: $1";;
    esac; shift
  done
  [ -n "$f" ] || usage
  [ -e "$f" ] || [ -L "$f" ] && die "이미 존재: $f"
  [ -d "$(dirname "$f")" ] || die "디렉터리 없음: $(dirname "$f")"
  if [ $raw -eq 1 ]; then
    truncate -s $SIZE "$f" || die "생성 실패"
  else
    command -v mkfs.fat >/dev/null || die "dosfstools 필요: sudo apt install dosfstools"
    # -C: 이미지 직접 생성(1440KiB, 플로피 기하 자동). hidden 섹터 0(DOS 표준)
    mkfs.fat -C -F 12 -s 1 -r 224 -f 2 -M 0xF0 ${label:+-n "$label"} "$f" 1440 >/dev/null \
      || { rm -f "$f"; die "포맷 실패"; }
  fi
  echo "생성: $f ($([ $raw -eq 1 ] && echo raw || echo FAT12))"
}

mnt(){
  local ro=0 f="" d=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --ro) ro=1;;
      *) if [ -z "$f" ]; then f="$1"; elif [ -z "$d" ]; then d="$1"; else die "인자 과다: $1"; fi;;
    esac; shift
  done
  [ -f "$f" ] || die "이미지 없음: ${f:-?}"
  [ -n "$d" ] || d=$(mp_of "$f")
  findmnt -M "$d" >/dev/null 2>&1 && die "이미 마운트됨: $d"
  [ $ro -eq 0 ] && [ ! -w "$f" ] && die "이미지 쓰기 권한 없음 (chmod u+w 또는 --ro)"
  local o="loop,uid=$(id -u),gid=$(id -g),umask=022,flush"
  [ $ro -eq 1 ] && o="$o,ro"
  SU mkdir -p "$d" || die "디렉터리 생성 실패"
  SU mount -t vfat -o "$o" "$f" "$d" || { SU rmdir "$d" 2>/dev/null; die "마운트 실패"; }
  echo "마운트($([ $ro -eq 1 ] && echo ro || echo rw)): $d"
}

umnt(){
  local t="${1:-}" d
  [ -n "$t" ] || usage
  if [ -f "$t" ]; then d=$(mp_of "$t"); elif [ -d "/mnt/floppy/${t%/}" ]; then d="/mnt/floppy/${t%/}"; else d="${t%/}"; fi
  findmnt -M "$d" >/dev/null 2>&1 || die "마운트되어 있지 않음: $d"
  sync
  SU umount "$d" || die "해제 실패 (사용 중인 프로세스/탐색기 창 확인)"
  SU rmdir "$d" 2>/dev/null
  echo "해제 완료: $d"
}

c="${1:-}"; shift || true
case "$c" in
  new) new "$@";;
  mount) mnt "$@";;
  umount|umnt) umnt "$@";;
  *) usage;;
esac
