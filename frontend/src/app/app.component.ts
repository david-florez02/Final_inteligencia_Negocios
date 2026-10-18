import { Component, inject } from '@angular/core';
import { MatButtonModule } from '@angular/material/button';
import { MatBadgeModule } from '@angular/material/badge';
import { MatIconModule } from '@angular/material/icon';
import { MatToolbarModule } from '@angular/material/toolbar';
import { Router, RouterLink, RouterOutlet } from '@angular/router';

import { CartService } from './core/cart.service';
import { SupabaseService } from './core/supabase.service';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, RouterLink, MatToolbarModule, MatButtonModule, MatIconModule, MatBadgeModule],
  template: `
    <mat-toolbar color="primary">
      <span class="brand">TechStore</span>
      <span class="spacer"></span>
      <a mat-button routerLink="/catalog">Catálogo</a>
      <a mat-button routerLink="/cart" matBadge="{{ cart.totalUnits() }}" [matBadgeHidden]="cart.totalUnits() === 0" [matBadgeColor]="'accent'">
        <mat-icon>shopping_cart</mat-icon>
        Carrito
      </a>
      @if (app.session()) {
        @if (app.isAdmin()) {
          <a mat-button routerLink="/admin">Administración</a>
        }
        <a mat-button routerLink="/profile">Mi perfil</a>
        <button mat-button (click)="logout()">Salir</button>
      } @else {
        <a mat-button routerLink="/login">Entrar</a>
        <a mat-button routerLink="/register">Registrarse</a>
      }
    </mat-toolbar>
    <main class="content">
      <router-outlet />
    </main>
  `,
  styles: [`
    :host { display: block; height: 100%; }
    .brand { font-weight: 700; letter-spacing: 1px; margin-right: 16px; }
    .spacer { flex: 1 1 auto; }
    .content { padding: 24px; max-width: 1200px; margin: 0 auto; }
  `],
})
export class AppComponent {
  readonly app = inject(SupabaseService);
  readonly cart = inject(CartService);
  private router = inject(Router);

  async logout(): Promise<void> {
    await this.app.signOut();
    void this.router.navigate(['/catalog']);
  }
}
