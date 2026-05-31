const SPREADSHEET_ID = '1hdEFMTRURThsg8SosbPIEFP8vUeZ9_0TOrm747RztSA';
const SHEET_NAME = 'Absensi Digital';

function doGet() {
  return ContentService
    .createTextOutput(JSON.stringify({ ok: true, message: 'MM attendance webhook active' }))
    .setMimeType(ContentService.MimeType.JSON);
}

function doPost(e) {
  const payload = JSON.parse((e && e.postData && e.postData.contents) || '{}');
  const spreadsheet = SpreadsheetApp.openById(SPREADSHEET_ID);
  const sheet = spreadsheet.getSheetByName(SHEET_NAME) || spreadsheet.insertSheet(SHEET_NAME);

  if (sheet.getLastRow() === 0) {
    sheet.appendRow([
      'Nama',
      'Waktu',
      'Jenis Absen',
      'Username',
      'Tanggal',
      'Status',
      'Catatan',
      'Kode QR',
      'Waktu Sinkron'
    ]);
  }

  sheet.appendRow([
    payload.nama || '',
    payload.waktu || '',
    payload.jenisAbsen || '',
    payload.username || '',
    payload.tanggal || '',
    payload.status || '',
    payload.catatan || '',
    payload.kodeQr || '',
    new Date()
  ]);

  return ContentService
    .createTextOutput(JSON.stringify({ ok: true }))
    .setMimeType(ContentService.MimeType.JSON);
}
