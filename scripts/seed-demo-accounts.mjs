/**
 * Demo account seeder for the isolated chatgptproject1 Supabase project.
 * Run on your own computer, NEVER in browser or bundled Vite code.
 * Requires SUPABASE_SERVICE_ROLE_KEY in the terminal process environment.
 * Does NOT modify any other Supabase project.
 */
import {createClient} from '@supabase/supabase-js';
import {randomBytes} from 'node:crypto';
import {writeFileSync,existsSync} from 'node:fs';
import {resolve} from 'node:path';

const PROJECT_REF='kkkolpwdxzgscpbagmfk';
const PROJECT_URL=`https://${PROJECT_REF}.supabase.co`;
const CREDENTIAL_FILE=resolve('demo-credentials.local.json');
const key=process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!key) {
 console.error('Missing SUPABASE_SERVICE_ROLE_KEY. Read README.md for safe local setup.');
 process.exit(1);
}
if (process.env.VITE_SUPABASE_URL && process.env.VITE_SUPABASE_URL !== PROJECT_URL) {
 console.error('Project mismatch. Refusing to modify any project other than chatgptproject1.');
 process.exit(1);
}
if (existsSync(CREDENTIAL_FILE)) {
 console.error('Credentials file already exists. Stop to avoid overwriting saved demo passwords.');
 process.exit(1);
}

const supabase=createClient(PROJECT_URL,key,{auth:{autoRefreshToken:false,persistSession:false}});
const accounts=[
 {email:'demo.customer@example.com',name:'Demo Customer',role:'customer'},
 {email:'demo.pharmacy1@example.com',name:'Shirpur Central Pharmacy',role:'store_owner',
  store:{name:'Shirpur Central Pharmacy',address:'Main Road, Shirpur, Maharashtra 425405, India',lat:21.3503,lng:74.8804,pincodes:['425405','425406']}},
 {email:'demo.pharmacy2@example.com',name:'Shirpur Care Pharmacy',role:'store_owner',
  store:{name:'Shirpur Care Pharmacy',address:'Bus Stand Road, Shirpur, Maharashtra 425405, India',lat:21.3568,lng:74.8867,pincodes:['425405']}},
 {email:'demo.pharmacy3@example.com',name:'Eastside Medical Store',role:'store_owner',
  store:{name:'Eastside Medical Store',address:'Shirpur East, Dhule District, Maharashtra 425405, India',lat:21.3462,lng:74.901,pincodes:['425405','425404']}},
 {email:'demo.pharmacy4@example.com',name:'Shirpur Health Point',role:'store_owner',
  store:{name:'Shirpur Health Point',address:'Shirpur North, Dhule District, Maharashtra 425405, India',lat:21.3688,lng:74.8751,pincodes:['425405','425406']}}
];

function assertOk(error,step){if(error)throw new Error(`${step}: ${error.message}`);}
async function allUsers(){
 const users=[];
 for(let page=1;page<50;page++){
  const {data,error}=await supabase.auth.admin.listUsers({page,perPage:1000});
  assertOk(error,'List users');
  users.push(...(data.users||[]));
  if((data.users||[]).length<1000)break;
 }
 return users;
}

const existing=await allUsers();
const {data:medicines,error:medErr}=await supabase.from('medicines').select('id,name').order('name');
assertOk(medErr,'Load medicines');
if(!medicines?.length)throw new Error('Missing medicines. Apply the database migrations first.');

const results=[];
function saveCredentials(){
 writeFileSync(CREDENTIAL_FILE,JSON.stringify({
  project_ref:PROJECT_REF,generated_at:new Date().toISOString(),
  note:'Local-only demonstration credentials. Do not commit or share this file.',
  accounts:results
 },null,2),{encoding:'utf8',mode:0o600});
}
for(const [index,a] of accounts.entries()){
 if(existing.some(u=>u.email?.toLowerCase()===a.email.toLowerCase())){
  console.log('Already exists, skipped:',a.email);
  results.push({email:a.email,role:a.role,password:null,status:'already exists; password unchanged'});
  saveCredentials();
  continue;
 }
 const password=randomBytes(15).toString('base64url')+'aA1!';
 const {data:userData,error:userErr}=await supabase.auth.admin.createUser({
  email:a.email,password,email_confirm:true,
  user_metadata:{full_name:a.name,role:a.role,phone:''}
 });
 assertOk(userErr,'Create '+a.email);
 const user=userData.user;
 if(!user)throw new Error('Supabase did not return a user for '+a.email);
 const {data:profile,error:profileErr}=await supabase.from('profiles').select('id,role').eq('id',user.id).single();
 assertOk(profileErr,'Validate signup profile for '+a.email);
 if(profile.role!==a.role)throw new Error('Role mismatch for '+a.email);
 if(a.store){
  const {data:store,error:storeErr}=await supabase.from('stores').insert({
   owner_id:user.id,name:a.store.name,address:a.store.address,lat:a.store.lat,lng:a.store.lng,
   is_open:true,offers_delivery:true,serviceable_pincodes:a.store.pincodes
  }).select('id').single();
  assertOk(storeErr,'Create store for '+a.email);
  const rows=medicines.map((med,m)=>({
   store_id:store.id,medicine_id:med.id,price:Number((22+m*8+index*3).toFixed(2)),
   stock:((m+index)%7===0)?0:((m+index)%4+3)
  }));
  const {error:invErr}=await supabase.from('store_inventory').insert(rows);
  assertOk(invErr,'Seed inventory for '+a.email);
 }
 results.push({email:a.email,role:a.role,password,status:'created'});
 saveCredentials();
 console.log('Created:',a.email, a.role);
}

console.log('\nCreated credentials file:',CREDENTIAL_FILE);
console.log('Never commit this file. This script is safe to rerun: it never resets existing user passwords.');
console.log('Verify sign-in in the app for each role. These demo accounts are not for real patient data.');
