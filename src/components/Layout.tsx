import {NavLink,Link,useNavigate} from 'react-router-dom';
import {Pill,ClipboardList,PackageSearch,Boxes,LogOut} from 'lucide-react';
import {BRAND_NAME} from '../config/brand';
import {supabase} from '../lib/supabase';
import {useAuth} from '../features/auth/AuthProvider';

export default function Layout({children}:{children:React.ReactNode}){
 const {user,role}=useAuth();
 const navigate=useNavigate();
 const home=role==='store_owner'?'/store':'/catalog';
 return <>
  <header className="site-header"><div className="container header-inner">
   <Link className="brand-link" to={home} aria-label={BRAND_NAME+' home'}>
    <span className="brand-mark"><Pill aria-hidden="true"/></span>
    <span className="brand-word">{BRAND_NAME}</span>
   </Link>
   {user&&<nav className="site-nav" aria-label="Primary navigation">
    {role==='customer'?<>
     <NavLink to="/catalog" className={({isActive})=>'nav-link'+(isActive?' active':'')}><PackageSearch aria-hidden="true"/> Find medicines</NavLink>
     <NavLink to="/orders" className={({isActive})=>'nav-link'+(isActive?' active':'')}><ClipboardList aria-hidden="true"/> My orders</NavLink>
    </>:<>
     <NavLink to="/store" end className={({isActive})=>'nav-link'+(isActive?' active':'')}><ClipboardList aria-hidden="true"/> Orders</NavLink>
     <NavLink to="/store/inventory" className={({isActive})=>'nav-link'+(isActive?' active':'')}><Boxes aria-hidden="true"/> Inventory</NavLink>
    </>}
   </nav>}
   {user&&<div className="header-actions"><span className="header-label">{role==='store_owner'?'STORE PORTAL':'CUSTOMER PORTAL'}</span><span className="header-separator"/><button className="btn-outline" onClick={async()=>{await supabase.auth.signOut();navigate('/login')}}><LogOut size={15} aria-hidden="true"/> Sign out</button></div>}
  </div></header>
  <main className="site-main">{children}</main>
  <footer className="footer">© {new Date().getFullYear()} {BRAND_NAME} · College project. Not for real medical use.</footer>
 </>;
}