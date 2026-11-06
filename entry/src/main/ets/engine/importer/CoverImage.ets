/**
 * 封面字节的判定（**纯 TS，零依赖 → CI 可单测**）
 *
 * 为什么需要它：封面字节来源有四条（EPUB 的 coverHref / EPUB2 的封面页里抠出的图 /
 * MOBI 的 EXTH201 记录 / 以后可能的 PDF 首页渲染），任何一条都可能**拿错东西**——
 * 最典型的是 EPUB2 的 `<guide type="cover">` 指到一个 XHTML 封面页，
 * 把那一页的 XHTML 文本当成图片写进 cover.jpg。
 *
 * 这种错**不会报错**：`Image` 解不出来就画一片空白，看起来和"这本书没封面"一模一样，
 * 于是排查方向会跑到解析器上去。所以在落盘前按**文件头**判一次：不是图片就不写。
 */
export function isImageBytes(bytes: Uint8Array): boolean {
  const n: number = bytes.length;
  if (n < 12) {
    return false;
  }
  // JPEG：FF D8 FF
  if (bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) {
    return true;
  }
  // PNG：89 50 4E 47 0D 0A 1A 0A
  if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47 &&
    bytes[4] === 0x0D && bytes[5] === 0x0A && bytes[6] === 0x1A && bytes[7] === 0x0A) {
    return true;
  }
  // GIF：'GIF8'
  if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x38) {
    return true;
  }
  // WebP：'RIFF' .... 'WEBP'（第 8 字节起）
  if (bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
    bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) {
    return true;
  }
  // BMP：'BM'
  if (bytes[0] === 0x42 && bytes[1] === 0x4D) {
    return true;
  }
  return false;
}
