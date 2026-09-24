import LoginForm from './LoginForm'

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; redirectTo?: string }>
}) {
  const { error, redirectTo } = await searchParams
  // Middleware gắn ?redirectTo= khi đá về /login; chỉ nhận đường dẫn nội bộ. Không có thì về trang
  // chủ (chưa có nhân vật sẽ tự sang /create-character).
  const back = redirectTo && redirectTo.startsWith('/') && !redirectTo.startsWith('//') ? redirectTo : '/'
  return <LoginForm initialError={error ?? null} redirectTo={back} />
}
