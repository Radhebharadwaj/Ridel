import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "npm:@supabase/supabase-js@2"

// CORS headers Web browser errors rokne ke liye
const corsHeaders = {
  'Access-Control-Allow-Origin': '*', // Ise baad me apne domain se replace kar dena security ke liye
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  // 1. CORS Preflight request ko handle karna (Web browsers ke liye zaroori hai)
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 2. Initialize Supabase Admin Client (RLS bypass karke logs likhne aur upload karne ke liye)
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // 3. Token se User ID nikalna
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "No authorization header" }), { status: 401, headers: corsHeaders })
    }

    const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(authHeader.replace('Bearer ', ''))
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: corsHeaders })
    }

    // 4. File Read Karna
    const formData = await req.formData()
    const file = formData.get('file') as File
    
    if (!file) {
      return new Response(JSON.stringify({ error: "No file uploaded" }), { status: 400, headers: corsHeaders })
    }

    // 5. THE MAGIC NUMBER CHECK (DNA Test for PNG & JPG)
    const arrayBuffer = await file.arrayBuffer()
    const uint8Array = new Uint8Array(arrayBuffer.slice(0, 4))
    
    // PNG files hamesha 89 50 4E 47 se start hoti hain
    const isPNG = uint8Array[0] === 0x89 && uint8Array[1] === 0x50 && uint8Array[2] === 0x4E && uint8Array[3] === 0x47
    // JPG/JPEG files hamesha FF D8 FF se start hoti hain
    const isJPG = uint8Array[0] === 0xFF && uint8Array[1] === 0xD8 && uint8Array[2] === 0xFF

    if (!isPNG && !isJPG) {
      // 🚨 HACKER DETECTED! File extension galat hai ya DNA match nahi hua.
      
      // A. Log the attack
      await supabaseAdmin.from('security_logs').insert({
        user_id: user.id,
        violation_type: 'MALICIOUS_FILE_MAGIC_BYTES',
        attempted_file_name: file.name
      })

      // B. Add to Banned Users Table
      await supabaseAdmin.from('banned_users').insert({
        user_id: user.id,
        reason: 'Attempted malicious file upload'
      })

      // C. Account permanently suspend karna (10 saal ke liye)
      await supabaseAdmin.auth.admin.updateUserById(user.id, { ban_duration: '87600h' }) 

      return new Response(JSON.stringify({ error: "Security Violation: Account Suspended." }), { 
        status: 403, 
        headers: { ...corsHeaders, "Content-Type": "application/json" } 
      })
    }

    // 6. ALL CLEAR! File original aur safe hai. Ab ise Storage me upload karte hain.
    const fileExtension = isPNG ? 'png' : 'jpg'
    const filePath = `${user.id}/profile.${fileExtension}` // User ke khud ke folder me jayegi

    const { data, error: uploadError } = await supabaseAdmin.storage
      .from('avatars')
      .upload(filePath, file, {
        contentType: file.type,
        upsert: true // Agar pehle se photo hai toh replace kar dega
      })

    if (uploadError) {
      throw uploadError
    }

    // 7. Success Response
    return new Response(JSON.stringify({ message: "Upload successful!", path: filePath }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    })

  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    })
  }
})