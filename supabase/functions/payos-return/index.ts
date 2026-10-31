const deno = (globalThis as typeof globalThis & {
  Deno: { serve: (handler: (request: Request) => Response | Promise<Response>) => void }
}).Deno

deno.serve((request) => {
  const url = new URL(request.url)
  const status = url.searchParams.get('status') ?? 'PENDING'
  const cancelled = url.searchParams.get('cancel') === 'true'
  const paid = status === 'PAID' && !cancelled
  const title = paid ? 'Thanh toán thành công' : cancelled ? 'Bạn đã hủy thanh toán' : 'Thanh toán đang được xử lý'
  const message = paid
    ? 'PayOS đã ghi nhận giao dịch. Quay lại VinExpress để xem số dư được cập nhật.'
    : cancelled
      ? 'Bạn có thể quay lại VinExpress và tạo giao dịch mới khi cần.'
      : 'Vui lòng quay lại VinExpress sau ít phút. Số dư chỉ được cộng khi webhook PayOS xác nhận.'
  const color = paid ? '#00bfae' : '#d98b00'
  return new Response(`<!doctype html><html lang="vi"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><body style="margin:0;background:#f5fbfa;font-family:Arial,sans-serif;color:#173b38"><main style="max-width:480px;margin:10vh auto;padding:32px;text-align:center;background:#fff;border-radius:22px;box-shadow:0 12px 40px #173b3815"><div style="width:56px;height:56px;line-height:56px;margin:auto;border-radius:50%;background:${color};color:white;font-size:30px">${paid ? '✓' : '!'}</div><h1 style="font-size:24px;margin:22px 0 12px">${title}</h1><p style="line-height:1.6;color:#52716e">${message}</p><p style="font-size:13px;color:#819b99">Bạn có thể đóng trang này và trở lại ứng dụng.</p></main></body></html>`, {
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
  })
})
