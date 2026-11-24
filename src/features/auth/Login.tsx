import {useState} from 'react';
import {Navigate} from 'react-router-dom';
import {z} from 'zod';
import {ShieldCheck,ArrowRight,LockKeyhole,HeartPulse} from 'lucide-react';
import {supabase} from '../../lib/supabase';
import {useAuth} from './AuthProvider';
import type {Role} from '../../lib/types';

const emailSchema=z.string().email();
export default function Login(){
 const {user,role,refresh}=useAuth();
 const [signup,setSignup]=useState(false);
 const [email,setEmail]=useState('');
 const [password,setPassword]=useState('');
 const [name,setName]=useState('');
 const [phone,setPhone]=useState('');
 const [selectedRole,setSelectedRole]=useState<Role>('customer');
 const [error,setError]=useState('');
 const [busy,setBusy]=useState(false);
 if(user&&role)return <Navigate to={role==='store_owner'?'/store':'/catalog'} replace/>;
 async function submit(e:React.FormEvent){
  e.preventDefault();setError('');
  if(!emailSchema.safeParse(email).success){setError('Enter a valid email.');return}
  if(password.length<6){setError('Password must contain at least 6 characters.');return}
  setBusy(true);
  try{
   if(signup){
    if(!name.trim()){setError('Enter your full name.');return}
    const {error}=await supabase.auth.signUp({email,password,options:{data:{full_name:name.trim(),phone:phone.trim(),role:selectedRole}}});
    if(error)throw error;
    setError('Account created. Confirm your email if required, then sign in.');setSignup(false);
   }else{
    const {error}=await supabase.auth.signInWithPassword({email,password});
    if(error)throw error;
    await refresh();
   }
  }catch(e){setError(e instanceof Error?e.message:'Unable to sign in')}
  finally{setBusy(false)}
 }
 return <div className="auth-page">
  <aside className="auth-aside" aria-label="About FindMedicine">
   <div><div className="eyebrow"><HeartPulse size={19} style={{display:'inline-block',verticalAlign:'middle',marginRight:9}}/> CARE, SIMPLIFIED</div>
    <h2>Everything you need, in one convenient place.</h2>
    <p>Find medicines, choose a nearby pharmacy, and keep track of your orders with a clear, practical experience.</p>
   </div>
   <div className="trust-line"><ShieldCheck size={19}/> Designed with privacy and clarity in mind</div>
  </aside>
  <div className="auth-card">
   <div className="page-kicker"><LockKeyhole size={14}/> SECURE ACCOUNT ACCESS</div>
   <div className="panel">
    <h1 className="section-title">{signup?'Create your account':'Welcome back'}</h1>
    <p className="muted" style={{marginBottom:23}}>{signup?'Enter your details to get started.':'Sign in to manage your medicines and orders.'}</p>
    <form onSubmit={submit} className="stack">
     {signup&&<>
      <label>Full name<input className="field" autoComplete="name" value={name} onChange={e=>setName(e.target.value)} required placeholder="Your full name"/></label>
      <label>Phone number<input className="field" autoComplete="tel" value={phone} onChange={e=>setPhone(e.target.value)} placeholder="Contact number"/></label>
      <label>Account type<select className="field" value={selectedRole} onChange={e=>setSelectedRole(e.target.value as Role)}><option value="customer">Customer</option><option value="store_owner">Pharmacy owner</option></select></label>
     </>}
     <label>Email address<input className="field" type="email" autoComplete="email" value={email} onChange={e=>setEmail(e.target.value)} required placeholder="you@example.com"/></label>
     <label>Password<input className="field" type="password" autoComplete={signup?'new-password':'current-password'} minLength={6} value={password} onChange={e=>setPassword(e.target.value)} required placeholder="At least 6 characters"/></label>
     {error&&<p role="alert" className={error.startsWith('Account created')?'muted':'error'}>{error}</p>}
     <button className="btn" disabled={busy}>{busy?'Please wait…':signup?'Create account':'Sign in'} <ArrowRight size={16}/></button>
    </form>
    <button className="btn-outline auth-switch" onClick={()=>{setSignup(!signup);setError('')}}>{signup?'Already registered? Sign in':'New to FindMedicine? Create an account'}</button>
   </div>
   <p className="muted" style={{fontSize:11,textAlign:'center',marginTop:18}}>For college demonstration only · No real medical transactions</p>
  </div>
 </div>;
}