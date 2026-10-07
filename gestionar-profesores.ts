// Edge Function "gestionar-profesores": crea, cambia contraseña y elimina profesores. Solo la puede usar un administrador.
import { createClient } from 'npm:@supabase/supabase-js@2'
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' }
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const url = Deno.env.get('SUPABASE_URL')!, anon = Deno.env.get('SUPABASE_ANON_KEY')!, svc = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const caller = createClient(url, anon, { global: { headers: { Authorization: req.headers.get('Authorization') || '' } } })
    const { data: { user } } = await caller.auth.getUser()
    if (!user) return json({ error: 'Su sesión venció. Vuelva a entrar.' }, 401)
    const admin = createClient(url, svc, { auth: { persistSession: false } })
    const { data: me } = await admin.from('profiles').select('role').eq('id', user.id).single()
    if (me?.role !== 'admin') return json({ error: 'Solo el administrador puede hacer esto.' }, 403)

    const b = await req.json()
    const isTeacher = async (id: string) => (await admin.from('profiles').select('role').eq('id', id).single()).data?.role === 'teacher'

    if (b.action === 'crear') {
      const email = String(b.email || '').trim().toLowerCase(), name = String(b.nombre || '').trim(), pw = String(b.password || '')
      if (!name) return json({ error: 'Escriba el nombre del profesor.' }, 400)
      if (!/^\S+@\S+\.\S+$/.test(email)) return json({ error: 'Escriba un correo válido.' }, 400)
      if (pw.length < 8) return json({ error: 'La contraseña debe tener al menos 8 caracteres.' }, 400)
      const { data, error } = await admin.auth.admin.createUser({ email, password: pw, email_confirm: true, user_metadata: { full_name: name } })
      if (error || !data.user) return json({ error: /already|registered|exists/i.test(error?.message || '') ? 'Ese correo ya tiene una cuenta.' : 'No se pudo crear la cuenta.' }, 400)
      const ids: string[] = Array.isArray(b.actividades) ? b.actividades.filter((x: unknown) => typeof x === 'string') : []
      if (ids.length) await admin.from('activity_teachers').insert(ids.map((a) => ({ activity_id: a, teacher_id: data.user!.id })))
      return json({ ok: true, id: data.user.id })
    }
    if (b.action === 'password') {
      if (String(b.password || '').length < 8) return json({ error: 'La contraseña debe tener al menos 8 caracteres.' }, 400)
      if (!(await isTeacher(String(b.id)))) return json({ error: 'Profesor no encontrado.' }, 404)
      const { error } = await admin.auth.admin.updateUserById(String(b.id), { password: String(b.password) })
      return error ? json({ error: 'No se pudo cambiar la contraseña.' }, 400) : json({ ok: true })
    }
    if (b.action === 'eliminar') {
      if (!(await isTeacher(String(b.id)))) return json({ error: 'Profesor no encontrado.' }, 404)
      const { error } = await admin.auth.admin.deleteUser(String(b.id))
      return error ? json({ error: 'No se pudo eliminar al profesor.' }, 400) : json({ ok: true })
    }
    return json({ error: 'Acción no válida.' }, 400)
  } catch (_e) {
    return json({ error: 'Ocurrió un error. Intente de nuevo.' }, 500)
  }
})
