import { Routes } from '@angular/router';

import { AuthGuard } from './guard/auth.guard';
import { RoleGuard } from './guard/role.guard';
import { CartPage } from './page/cart/cart.page';
import { CatalogPage } from './page/catalog/catalog.page';
import { CheckoutPage } from './page/checkout/checkout.page';
import { LoginPage } from './page/login/login.page';
import { ProfilePage } from './page/profile/profile.page';
import { RegisterPage } from './page/register/register.page';
import { AdminDashboardPage } from './page/admin/admin-dashboard.page';

export const appRoutes: Routes = [
  { path: '', pathMatch: 'full', redirectTo: 'catalog' },
  { path: 'catalog', component: CatalogPage },
  { path: 'cart', component: CartPage },
  { path: 'login', component: LoginPage },
  { path: 'register', component: RegisterPage },
  { path: 'checkout', component: CheckoutPage, canActivate: [AuthGuard] },
  { path: 'profile', component: ProfilePage, canActivate: [AuthGuard] },
  { path: 'admin', component: AdminDashboardPage, canActivate: [RoleGuard] },
  { path: '**', redirectTo: 'catalog' },
];
